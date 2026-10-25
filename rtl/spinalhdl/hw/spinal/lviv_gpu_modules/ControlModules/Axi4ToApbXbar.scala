package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.misc.SizeMapping

// Address map:
//   0x000 - 0x3FF  LUT (0x000 texture base, 0x200 texture size; 128 entries each)
//   0x400 - 0x47F  Command processor
//   0x480 - 0x7FF  Reserved
//   0x800 - 0x81F  Frontend config, 8 words
//   0x820 - 0x89F  Thread[0..3] regs, 8 words (32 B) each
//   0x8A0 - 0xEFF  Reserved
//   0xF00 - 0xF7F  Tile DMA
//   0xF80 - 0xFFF  Visibility DMA
// Address map metadata emitted to address_map.json (for parsing / plotting the APB map)
case class XbarSubRegion(
    name: String,
    mapping: SizeMapping, // Offset and size within the parent window
    entries: Int,
    entryBits: Int,
    access: String,
    description: String
)

case class XbarRegion(
    name: String,
    port: Apb3,
    mapping: SizeMapping,
    kind: String, // "table" (RAM-backed array) or "regs" (regif register block)
    description: String,
    regmap: Option[String] = None, // Slave's regif JSON, relative to address_map.json
    subregions: Seq[XbarSubRegion] = Nil
)

object Axi4ToApbXbar {
  val addressWidth = 12
  val idWidth = 4

  // Where the register blocks sit; the command processor writes them at these addresses
  val cpBase = 0x400
  val frontendBase = 0x800
  val threadBase = frontendBase + APBFrontendRegs.byteCount // 4 windows of ApbThreadRegs.byteCount
  val tileDmaBase = 0xf00
  val visDmaBase = 0xf80
  val dmaBytes = 0x080
}

case class Axi4ToApbXbar(
    masters: Int = 2,
    addressWidth: Int = 12,
    dataWidth: Int = 32,
    idWidth: Int = 4,
    inputFifoDepth: Int = 32,
    apbPipelineStages: Int = 1,
    lutWordCount: Int = 128 // Must match ApbLutRam wordCount
) extends Component {
  require(masters >= 1)
  require(inputFifoDepth >= 0)
  require(apbPipelineStages >= 0)

  // LUT window sized from ApbLutRam so the decoder mapping and slave PADDR width always match
  val lutBytes = ApbLutRam.byteCount(lutWordCount)
  require(isPow2(lutBytes) && lutBytes <= 0x800, s"LUT window ($lutBytes B) must fit below the frontend at 0x800")

  // The arbiter extends IDs with the master index to route responses back
  val apbBridge = Axi4SharedToApb3Bridge(
    addressWidth = addressWidth,
    dataWidth = dataWidth,
    idWidth = idWidth + log2Up(masters)
  )

  val axiConfig = apbBridge.axiConfig.copy(idWidth = idWidth)
  val apbConfig = apbBridge.apbConfig

  val lutApbConfig = apbConfig.copy(addressWidth = log2Up(lutBytes))
  val frontendApbConfig = apbConfig.copy(addressWidth = log2Up(APBFrontendRegs.byteCount))
  val threadApbConfig = apbConfig.copy(addressWidth = log2Up(ApbThreadRegs.byteCount))
  val dmaApbConfig = apbConfig.copy(addressWidth = log2Up(Axi4ToApbXbar.dmaBytes))
  val cpApbConfig = apbConfig.copy(addressWidth = log2Up(CommandProcessor.byteCount))

  val io = new Bundle {
    val m_axi = Vec(slave(Axi4(axiConfig)), masters)
    val lut = master(Apb3(lutApbConfig))
    val cp = master(Apb3(cpApbConfig))
    val frontend = master(Apb3(frontendApbConfig))
    val threadRegs = Vec(master(Apb3(threadApbConfig)), 4)
    val tileDma = master(Apb3(dmaApbConfig))
    val visDma = master(Apb3(dmaApbConfig))
  }

  noIoPrefix()

  // Vivado AXI naming (<prefix>_awaddr, ...) and aximm interface attributes on each master port
  for ((m, i) <- io.m_axi.zipWithIndex) {
    val prefix = s"m_axi_$i"
    m.flatten.foreach { signal =>
      val port = signal.getName().replace(s"${prefix}_", "").replace("_payload_", "").replace("_", "")
      signal.setName(s"${prefix}_$port")
      signal.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:aximm:1.0 $prefix ${port.toUpperCase}")
    }
    m.ar.valid.addAttribute("X_INTERFACE_MODE", "slave")
    m.ar.valid.addAttribute(
      "X_INTERFACE_PARAMETER",
      s"PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, ADDR_WIDTH $addressWidth, DATA_WIDTH $dataWidth, ID_WIDTH $idWidth, " +
        s"NUM_READ_OUTSTANDING $inputFifoDepth, NUM_WRITE_OUTSTANDING $inputFifoDepth, MAX_BURST_LENGTH 1"
    )
  }

  // Request-side FIFOs absorb bursts of accesses per master; the APB side drains them one at a time.
  val arbiter = Axi4SharedArbiter(
    outputConfig = apbBridge.axiConfig,
    readInputsCount = 0,
    writeInputsCount = 0,
    sharedInputsCount = masters,
    routeBufferSize = 4
  )

  for ((m, i) <- io.m_axi.zipWithIndex) {
    val axiBuffered = Axi4(axiConfig)
    axiBuffered.ar << m.ar.queue(inputFifoDepth)
    axiBuffered.aw << m.aw.queue(inputFifoDepth)
    axiBuffered.w << m.w.queue(inputFifoDepth)
    m.r << axiBuffered.r
    m.b << axiBuffered.b
    arbiter.io.sharedInputs(i) <> Axi4ToAxi4Shared(axiBuffered)
  }

  // Round-robin between masters
  apbBridge.io.axi <> arbiter.io.output

  val lutSlice = Apb3RegSlice(lutApbConfig, apbPipelineStages)
  val frontendSlice = Apb3RegSlice(frontendApbConfig, apbPipelineStages)
  val threadSlices = Array.fill(4)(Apb3RegSlice(threadApbConfig, apbPipelineStages))
  val cpSlice = Apb3RegSlice(cpApbConfig, apbPipelineStages)
  lutSlice.io.m >> io.lut
  cpSlice.io.m >> io.cp
  frontendSlice.io.m >> io.frontend
  for (i <- 0 until 4) threadSlices(i).io.m >> io.threadRegs(i)
  val tileDmaSlice = Apb3RegSlice(dmaApbConfig, apbPipelineStages)
  val visDmaSlice = Apb3RegSlice(dmaApbConfig, apbPipelineStages)
  tileDmaSlice.io.m >> io.tileDma
  visDmaSlice.io.m >> io.visDma

  // Frontend window followed by the 4 thread windows, each sized by its slave module
  val frontendBase = Axi4ToApbXbar.frontendBase
  val threadBase = Axi4ToApbXbar.threadBase

  // LUT tables, laid out by ApbLutRam
  val lutSubregions = Seq(
    XbarSubRegion(
      "texture_base",
      ApbLutRam.baseRegion(lutWordCount),
      lutWordCount,
      ApbLutRam.baseEntryBits,
      "RW",
      "Texture base address per entry"
    ),
    XbarSubRegion(
      "texture_size",
      ApbLutRam.sizeRegion(lutWordCount),
      lutWordCount,
      ApbLutRam.sizeEntryBits,
      "RW",
      "Texture size code per entry (low bits of each word)"
    )
  )

  // Decoded windows in address order; also used to emit the JSON address map
  val addressMap = List(
    XbarRegion(
      "Texture LUT",
      lutSlice.io.s,
      SizeMapping(0x000, lutBytes),
      "table",
      s"Texture LUT, $lutWordCount entries",
      subregions = lutSubregions
    ),
    XbarRegion(
      "Command Processor",
      cpSlice.io.s,
      SizeMapping(Axi4ToApbXbar.cpBase, CommandProcessor.byteCount),
      "regs",
      "Command processor: renders a frame on one START",
      Some("../CommandProcessor/command_processor_regmap.json")
    ),
    XbarRegion(
      "Front-end",
      frontendSlice.io.s,
      SizeMapping(frontendBase, APBFrontendRegs.byteCount),
      "regs",
      "Front-end status, tile index and thread reset",
      Some("../APBFrontendRegs/apb_front_end_regmap.json")
    )
  ) ++ (0 until 4).map { i =>
    XbarRegion(
      s"Thread #$i",
      threadSlices(i).io.s,
      SizeMapping(threadBase + i * ApbThreadRegs.byteCount, ApbThreadRegs.byteCount),
      "regs",
      s"Thread $i status, z-buffer clear, cache control",
      Some("../ApbThreadRegs/apb_thread_regmap.json")
    )
  } ++ List(
    XbarRegion(
      "Tile DMA",
      tileDmaSlice.io.s,
      SizeMapping(Axi4ToApbXbar.tileDmaBase, Axi4ToApbXbar.dmaBytes),
      "regs",
      "Tile DMA (AxiTileDma)",
      Some("../AxiTileDma/axi_tile_dma_regmap.json")
    ),
    XbarRegion(
      "Visibility DMA",
      visDmaSlice.io.s,
      SizeMapping(Axi4ToApbXbar.visDmaBase, Axi4ToApbXbar.dmaBytes),
      "regs",
      "Visibility DMA (AxiVisibilityDma)",
      Some("../AxiVisibilityDma/axi_visibility_dma_regmap.json")
    )
  )

  // Apb3Decoder hands each slave PADDR truncated to its width (no base subtraction),
  // so every window must be a power of 2 aligned to its own size, and windows must not overlap
  for (r <- addressMap) {
    require(
      isPow2(r.mapping.size) && r.mapping.base % r.mapping.size == 0,
      s"${r.name} window (base ${r.mapping.base}, size ${r.mapping.size}) is not size-aligned"
    )
    for (sub <- r.subregions) {
      require(sub.mapping.end < r.mapping.size, s"${r.name}.${sub.name} lies outside its window")
    }
  }
  for ((a, b) <- addressMap.zip(addressMap.tail)) {
    require(a.mapping.end < b.mapping.base, s"${a.name} window overlaps ${b.name}")
  }

  val decoder = Apb3Decoder(
    master = apbBridge.io.apb,
    slaves = addressMap.map(r => r.port -> r.mapping)
  )

  // JSON address map: every decoded window, LUT tables as subregions, and the reserved gaps,
  // so tools can parse and plot the full APB space. "regmap" points at the slave's regif JSON.
  // Addresses are numbers, as in the regif JSON; only the reserved gaps' names carry them in hex.
  def addressMapJson: String = {
    def hex(v: BigInt): String = f"0x${v.toLong}%03X"
    def span(base: BigInt, size: BigInt): String =
      s""""base": $base, "end": ${base + size - 1}, "size": $size"""

    val total = BigInt(1) << addressWidth

    val regions = addressMap.map { r =>
      val subregions = r.subregions.map { sub =>
        val fields = Seq(
          s""""name": "${sub.name}"""",
          s""""kind": "table"""",
          span(r.mapping.base + sub.mapping.base, sub.mapping.size),
          s""""entries": ${sub.entries}""",
          s""""entry_stride": ${sub.mapping.size / sub.entries}""",
          s""""entry_bits": ${sub.entryBits}""",
          s""""access": "${sub.access}"""",
          s""""description": "${sub.description}""""
        )
        "      {" + fields.mkString(", ") + "}"
      }
      val fields = Seq(
        s""""name": "${r.name}"""",
        s""""kind": "${r.kind}"""",
        span(r.mapping.base, r.mapping.size),
        s""""description": "${r.description}""""
      ) ++ r.regmap.map(path => s""""regmap": "$path"""") ++
        (if (subregions.nonEmpty) Seq(subregions.mkString("\"subregions\": [\n", ",\n", "\n    ]")) else Nil)
      r.mapping.base -> ("    {" + fields.mkString(", ") + "}")
    }

    // Reserved gaps between decoded windows (accesses there are not decoded)
    val gapStarts = BigInt(0) +: addressMap.map(_.mapping.end + 1)
    val gapEnds = addressMap.map(_.mapping.base) :+ total
    val gaps = gapStarts.zip(gapEnds).collect {
      case (start, stop) if stop > start =>
        start -> s"""    {"name": "reserved_${hex(start)}", "kind": "reserved", ${span(
            start,
            stop - start
          )}, "description": "Not decoded"}"""
    }

    val bus =
      s"""  "bus": {"protocol": "APB3", "address_width": $addressWidth, "data_width": $dataWidth, "size": $total}"""
    (regions ++ gaps).sortBy(_._1).map(_._2).mkString(s"{\n$bus,\n  \"regions\": [\n", ",\n", "\n  ]\n}\n")
  }
}

object Axi4ToApbXbarVerilog extends App {
  val targetDirectory = "rtl/Axi4ToApbXbar"
  val report = SpinalConfig(
    targetDirectory = targetDirectory,
    defaultConfigForClockDomains = ClockDomainConfig(
      resetActiveLevel = LOW,
      resetKind = SYNC
    )
  ).withPrivateNamespace.generateVerilog(Axi4ToApbXbar())

  java.nio.file.Files.writeString(
    java.nio.file.Paths.get(targetDirectory, "address_map.json"),
    report.toplevel.addressMapJson
  )
}
