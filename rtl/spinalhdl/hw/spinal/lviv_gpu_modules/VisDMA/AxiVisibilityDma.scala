package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._
import spinal.lib.fsm._

// =============================================================================
// Configuration for AxiVisibilityDma
// =============================================================================
case class AxiVisibilityDmaConfig(
    addressWidth: Int = 32, // Address width (32 up to 64 bits)
    axiDataWidth: Int = 128, // AXI4 Read Master data width (a power of 2): visibility bits a beat
    bttWidth: Int = 19, // DataMover BTT (Bytes To Transfer) width (up to 23 bits)
    defaultBttLimit: Int = 4096, // BTT_LIMIT's reset value, triangles a command
    maxTiles: Int = 64, // Tiles a frame can have (TILE_COUNT up to this)
    triangleSizeBytes: Int = 96, // Triangle data footprint in bytes (96 B: odd triangles start 32 B into a 64 B beat)
    maxOutstandingReads: Int = 8, // Max outstanding AXI4 Read address transactions
    cmdFifoDepth: Int = 64, // Depth of DataMover command FIFO (64 entries reduces backpressure)
    stsFifoDepth: Int = 4, // Depth of DataMover status FIFO (4 entries since consumed 1 per clock)
    vbFifoDepth: Int = 256, // Depth of the FIFO of beats with an edge
    useAutoAdvance: Boolean = true // Support automatic tile index advancing (0..TILE_COUNT-1)
) {
  require(maxTiles >= 1, s"maxTiles ($maxTiles) must be at least 1")
  val tileIndexWidth: Int = log2Up(maxTiles)
  val tileCountWidth: Int = log2Up(maxTiles + 1)
  require(isPow2(axiDataWidth) && axiDataWidth >= 128, "axiDataWidth must be a power of 2, at least 128")
  require(addressWidth >= 32 && addressWidth <= 64, "addressWidth must be between 32 and 64 bits")
  require(triangleSizeBytes > 0 && triangleSizeBytes % 32 == 0, "triangleSizeBytes must be a multiple of 32")
  require(cmdFifoDepth >= 4 && isPow2(cmdFifoDepth), "cmdFifoDepth must be a power of 2 >= 4")
  require(stsFifoDepth >= 4 && isPow2(stsFifoDepth), "stsFifoDepth must be a power of 2 >= 4")
  require(vbFifoDepth >= 32 && isPow2(vbFifoDepth), "vbFifoDepth must be a power of 2 >= 32")
  require(
    bttWidth >= 8 && bttWidth <= 23,
    s"bttWidth ($bttWidth) must be between 8 and 23 bits (Xilinx DataMover limit)"
  )

  // Triangle sizes are multiples of 32 B, so triangle addresses are carried in 32 B units
  val triAlignBytes: Int = 32
  val triAlignShift: Int = 5
  val triUnits: Int = triangleSizeBytes / triAlignBytes // Triangle size in 32 B units (3 for 96 B)
  val triWordAddrWidth: Int = addressWidth - triAlignShift // Address truncated by triAlignShift bits
  val axiBytesPerBeat: Int = axiDataWidth / 8 // 16 bytes for 128-bit
  val axiBeatShift: Int = log2Up(axiBytesPerBeat) // 4 bits for 16 bytes

  // The visibility buffer: each tile's bits, one per triangle, in 4 KiB chunks: chunk c of tile t
  // is 4 KiB page c * TILE_COUNT + t from VB_BASE
  val chunkShift: Int = 12
  val trianglesPerBeat: Int = axiDataWidth
  val chunkBeats: Int = (1 << chunkShift) / axiBytesPerBeat // 256 for 128-bit
  val triIndexWidth: Int = (addressWidth - log2Up(triangleSizeBytes) + 1) min 32 // 26: 4 GiB of 96 B triangles
  val beatIndexWidth: Int = triIndexWidth - log2Up(trianglesPerBeat)
  val chunkIndexWidth: Int = beatIndexWidth - log2Up(chunkBeats)

  // The edges of a beat, in groups: a group's turn, then an edge's in it, are two short loops
  val edgeGroupBits: Int = 8
  val edgeGroups: Int = trianglesPerBeat / edgeGroupBits
  val vbFifoMargin: Int = 8 // Entries left free: the beats on their way when R's ready falls

  // Maximum triangles in a single BTT transfer: count * triangleSizeBytes must fit in bttWidth bits
  val maxBttTriangles: Int = ((1 << bttWidth) - 1) / triangleSizeBytes // 5461 for 96 B @ 19 bits
  val bttTriCountWidth: Int = log2Up(maxBttTriangles + 1) // 13 bits for 96 B @ 19 bits
  val bttUnitsWidth: Int = bttTriCountWidth + log2Up(triUnits + 1) // count * triUnits
  require(
    defaultBttLimit >= 1 && defaultBttLimit <= maxBttTriangles,
    s"defaultBttLimit ($defaultBttLimit) must be between 1 and $maxBttTriangles"
  )

  // AMD / Xilinx LogiCORE IP AXI DataMover (PG022) Command Width
  // 72 bits for 32-bit address, 104 bits for 64-bit address
  val cmdWidth: Int = if (addressWidth <= 32) 72 else 104
  val stsWidth: Int = 8

  def getAxi4ReadConfig: Axi4Config = Axi4Config(
    addressWidth = addressWidth,
    dataWidth = axiDataWidth,
    idWidth = 4,
    useBurst = true,
    useSize = true,
    useLen = true,
    useLast = true,
    useResp = true,
    useId = true
  )

  def getApbConfig: Apb3Config = Apb3Config(
    addressWidth = 7,
    dataWidth = 32
  )
}

// =============================================================================
// Internal Compact Command Representation for DataMover FIFO
// =============================================================================
case class DataMoverCmdCompact(c: AxiVisibilityDmaConfig) extends Bundle {
  val triWordAddr = UInt(c.triWordAddrWidth bits) // Truncated triangle address (byte address >> alignment shift)
  val bttUnits = UInt(c.bttUnitsWidth bits) // BTT in 32 B units (triangle count * triUnits)
  val tag = Bits(4 bits)
}

// =============================================================================
// The visibility scan's bundles
// =============================================================================
// A beat with an edge, in vbFifo
case class VisBeat(c: AxiVisibilityDmaConfig) extends Bundle {
  val edges = Bits(c.trianglesPerBeat bits) // bit i: triangle i and the one before it differ
  val groups = Bits(c.edgeGroups bits) // the groups of edges with one
  val index = UInt(c.beatIndexWidth bits)
  val last = Bool() // the tile's last beat
}

// A run's first triangle or the one past its last, or the end of the tile's bits
case class VisEdge(c: AxiVisibilityDmaConfig) extends Bundle {
  val triangle = UInt(c.triIndexWidth bits)
  val end = Bool()
}

case class VisRun(c: AxiVisibilityDmaConfig) extends Bundle {
  val length = UInt(c.triIndexWidth bits)
  val offset = UInt(c.triWordAddrWidth bits) // from TRI_BASE
}

case class VisRunAddress(c: AxiVisibilityDmaConfig) extends Bundle {
  val length = UInt(c.triIndexWidth bits)
  val triWordAddr = UInt(c.triWordAddrWidth bits)
  val over = Bool() // past BTT_LIMIT
}

// =============================================================================
// Visibility DMA Command Engine
// =============================================================================
class AxiVisibilityDma(
    val config: AxiVisibilityDmaConfig = AxiVisibilityDmaConfig(),
    val dmClockDomain: ClockDomain = null
) extends Component {

  // DataMover Clock Domain (if null, operates synchronously in default clockDomain)
  val dmClock = if (dmClockDomain != null) dmClockDomain else ClockDomain.current
  val isDualClock = (dmClockDomain != null) && (dmClockDomain != ClockDomain.current)

  val io = new Bundle {
    // 1. APB3 Slave Interface for Register Programming (aclk domain)
    val s_apb = slave(Apb3(config.getApbConfig))

    // 2. AXI4 Read Master Interface for Visibility Buffer (aclk domain)
    val m_axi_vb = master(Axi4ReadOnly(config.getAxi4ReadConfig))

    // 3. AXI-Stream Master for DataMover Commands (dmClock domain)
    val m_axis_datamover_cmd = master(Stream(Bits(config.cmdWidth bits)))

    // 4. AXI-Stream Slave for DataMover Status (dmClock domain)
    val s_axis_datamover_sts = slave(Stream(Bits(config.stsWidth bits)))

    // 5. Discrete Engine Status Outputs (aclk domain)
    val ready = out Bool () // Asserted when engine is IDLE and ready for a new START trigger
    val irq = out Bool () // Combined Interrupt output (masked)
    val irq_done = out Bool () // Dedicated Tile Done Interrupt output (masked)
    val irq_error = out Bool () // Dedicated Error Interrupt output (masked)
    val irq_frame_done = out Bool () // Dedicated Frame Done Interrupt output (masked)

    // 6. The triangle stream, for the stall counters (aclk domain)
    val tri_stream_valid = in Bool () // the DataMover offers a beat
    val core_stall = in Bool () // a triangle waits for the core
  }

  noIoPrefix()

  // Vivado standard AXI4 memory-mapped bus port naming helper
  def renameAxiForVivado(bundle: Bundle, prefix: String): Unit = {
    bundle.flatten.foreach { signal =>
      val name = signal.getName()
      val cleanName = name
        .replaceFirst("^io_", "")
        .replace(s"${prefix}_", "")
        .replace("_payload_", "")
        .replace("_payload", "")
        .replace("_", "")

      signal.setName(s"${prefix}_${cleanName}")
    }
  }

  // Vivado standard AXI4-Stream port naming and interface attribute helper
  def renameAxisForVivado[T <: Data](stream: Stream[T], prefix: String): Unit = {
    stream.valid.setName(s"${prefix}_tvalid")
    stream.ready.setName(s"${prefix}_tready")
    stream.payload.setName(s"${prefix}_tdata")

    stream.valid.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:axis:1.0 ${prefix} TVALID")
    stream.ready.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:axis:1.0 ${prefix} TREADY")
    stream.payload.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:axis:1.0 ${prefix} TDATA")
  }

  renameAxiForVivado(io.m_axi_vb, "m_axi_vb")
  renameAxisForVivado(io.m_axis_datamover_cmd, "m_axis_datamover_cmd")
  renameAxisForVivado(io.s_axis_datamover_sts, "s_axis_datamover_sts")

  // AXI4 memory-mapped interface Vivado attributes
  io.m_axi_vb.flatten.foreach { sig =>
    val name = sig.getName()
    val suffix = name.replace("m_axi_vb_", "").toUpperCase
    sig.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:aximm:1.0 m_axi_vb $suffix")
  }
  io.m_axi_vb.ar.valid.addAttribute(
    "X_INTERFACE_PARAMETER",
    s"NUM_READ_OUTSTANDING ${config.maxOutstandingReads}, READ_WRITE_MODE READ_ONLY"
  )

  // Vivado Interrupt Interface Attributes
  io.irq.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq INTERRUPT")
  io.irq.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_done.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_done INTERRUPT")
  io.irq_done.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_error.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_error INTERRUPT")
  io.irq_error.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_frame_done.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_frame_done INTERRUPT")
  io.irq_frame_done.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")

  // Clock & Reset IP packaging attributes with ASSOCIATED_BUSIF
  clockDomain.clock.setName("aclk")
  clockDomain.reset.setName("aresetn")
  clockDomain.clock.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:clock:1.0 aclk CLK")
  clockDomain.clock.addAttribute(
    "X_INTERFACE_PARAMETER",
    if (isDualClock) {
      "ASSOCIATED_BUSIF m_axi_vb, ASSOCIATED_RESET aresetn"
    } else {
      "ASSOCIATED_BUSIF m_axi_vb:m_axis_datamover_cmd:s_axis_datamover_sts, ASSOCIATED_RESET aresetn"
    }
  )
  clockDomain.reset.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:reset:1.0 aresetn RST")
  clockDomain.reset.addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")

  if (isDualClock) {
    dmClock.clock.setName("dm_clk")
    dmClock.reset.setName("dm_resetn")
    dmClock.clock.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:clock:1.0 dm_clk CLK")
    dmClock.clock.addAttribute(
      "X_INTERFACE_PARAMETER",
      "ASSOCIATED_BUSIF m_axis_datamover_cmd:s_axis_datamover_sts, ASSOCIATED_RESET dm_resetn"
    )
    dmClock.reset.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:reset:1.0 dm_resetn RST")
    dmClock.reset.addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")
  }

  // ===========================================================================
  // 1. APB3 REGISTER INTERFACE (via SpinalHDL regif)
  // ===========================================================================
  val busif = Apb3BusInterface(io.s_apb, (0x0000, 128), "AXI_VISIBILITY_DMA")

  // Internal hardware status signals
  val dmaBusy = RegInit(False)
  val draining = RegInit(False) // after SOFT_RESET
  val axiReadError = RegInit(False)
  val dmErrorFlag = RegInit(False)
  val dmLastStsReg = Reg(Bits(8 bits)) init (0)
  val cycleCounter = Reg(UInt(32 bits)) init (0)
  val statVisCount = Reg(UInt(32 bits)) init (0)
  val statCmdCount = Reg(UInt(32 bits)) init (0)
  val statStsCount = Reg(UInt(32 bits)) init (0)

  // 0x00: CONTROL REGISTER
  val REG_CTRL = busif.newRegAt(address = 0x00, doc = "DMA Control Register")
  val START = REG_CTRL.field(Bool(), W1P, doc = "Trigger visibility scan and command generation")
  val SOFT_RESET = REG_CTRL.field(Bool(), W1P, doc = "Software reset for engine and internal FIFOs")
  val IRQ_ENABLE = REG_CTRL.field(Bool(), RW, resetValue = 1, doc = "Global Interrupt Enable (1: enabled)")
  val AUTO_ADV_EN =
    if (config.useAutoAdvance) REG_CTRL.field(Bool(), RW, resetValue = 1, doc = "Enable auto-advancing tile index")
    else null
  val CNT_CLEAR = REG_CTRL.field(Bool(), W1P, doc = "Clear the stall counters")

  // 0x04: STATUS REGISTER (W1C fields are internal registers in regif)
  val REG_STATUS = busif.newRegAt(address = 0x04, doc = "DMA Status Register")
  val BUSY = REG_STATUS.field(Bool(), RO, doc = "Engine active busy status")
  val DONE = REG_STATUS.field(Bool(), W1C, doc = "Tile processing complete (Write 1 to clear)")
  val ERROR = REG_STATUS.field(Bool(), W1C, doc = "Error detected on AXI read or DataMover (Write 1 to clear)")
  val IRQ_STATUS = REG_STATUS.field(Bool(), W1C, doc = "Interrupt pending (Write 1 to clear)")
  val FRAME_DONE =
    if (config.useAutoAdvance)
      REG_STATUS.field(Bool(), W1C, doc = "Last of TILE_COUNT tiles completed, index wrapped (Write 1 to clear)")
    else null
  val AXI_ERR_FLAG = REG_STATUS.field(Bool(), RO, doc = "AXI Read Master Bus Error")
  val DM_ERR_FLAG = REG_STATUS.field(Bool(), RO, doc = "DataMover Status Error")

  BUSY := dmaBusy
  AXI_ERR_FLAG := axiReadError
  DM_ERR_FLAG := dmErrorFlag

  // 0x08: VB_BASE_ADDR_LOW (4 KiB aligned, the bits below reserved/ignored)
  val REG_VB_LOW = busif.newRegAt(address = 0x08, doc = "Visibility Buffer Base Address [31:0] (4 KiB aligned)")
  REG_VB_LOW.reserved(config.chunkShift bits)
  val VB_BASE_LOW = REG_VB_LOW.field(
    UInt((32 - config.chunkShift) bits),
    RW,
    resetValue = 0,
    doc = s"Visibility Buffer Base Address [31:${config.chunkShift}]: chunk c of tile t is 4 KiB page " +
      "c * TILE_COUNT + t from here"
  )

  // 0x0C: VB_BASE_ADDR_HIGH
  val REG_VB_HIGH = busif.newRegAt(address = 0x0c, doc = "Visibility Buffer Base Address [63:32]")
  val VB_BASE_HIGH =
    REG_VB_HIGH.field(UInt(32 bits), RW, resetValue = 0, doc = "Upper 32 bits of Visibility Buffer Base Address")

  // 0x10: TRI_BASE_ADDR_LOW (triAlignBytes aligned, bits [triAlignShift-1:0] reserved/ignored)
  val REG_TRI_LOW = busif.newRegAt(
    address = 0x10,
    doc = s"Triangle Geometry Base Address [31:0] (${config.triAlignBytes}-byte aligned)"
  )
  REG_TRI_LOW.reserved(config.triAlignShift bits)
  val TRI_BASE_LOW = REG_TRI_LOW.field(
    UInt((32 - config.triAlignShift) bits),
    RW,
    resetValue = 0,
    doc = s"Triangle Geometry Base Address [31:${config.triAlignShift}]"
  )

  // 0x14: TRI_BASE_ADDR_HIGH
  val REG_TRI_HIGH = busif.newRegAt(address = 0x14, doc = "Triangle Geometry Base Address [63:32]")
  val TRI_BASE_HIGH =
    REG_TRI_HIGH.field(UInt(32 bits), RW, resetValue = 0, doc = "Upper 32 bits of Triangle Geometry Base Address")

  // 0x18: TRI_COUNT (N)
  val REG_TRI_COUNT = busif.newRegAt(address = 0x18, doc = "Triangle Count (N)")
  val TRI_COUNT = REG_TRI_COUNT.field(
    UInt(32 bits),
    RW,
    resetValue = 0,
    doc = "Triangles in the frame: the bits of each tile's visibility"
  )

  // 0x1C: TILE_INDEX
  val REG_TILE_IDX = busif.newRegAt(address = 0x1c, doc = s"Active Tile Index (0..${config.maxTiles - 1})")
  val TILE_INDEX = REG_TILE_IDX.field(
    UInt(config.tileIndexWidth bits),
    RW,
    resetValue = 0,
    doc = s"The tile to scan (0..${config.maxTiles - 1})"
  )

  // 0x20: BTT_LIMIT (triangle count; BTT bytes = count * triangleSizeBytes)
  val REG_BTT_LIMIT = busif.newRegAt(address = 0x20, doc = "Max Triangles per DataMover Command")
  val BTT_LIMIT_TRI = REG_BTT_LIMIT.field(
    UInt(config.bttTriCountWidth bits),
    RW,
    resetValue = config.defaultBttLimit,
    doc = s"Max triangles per command (BTT = count * ${config.triangleSizeBytes} B; 0 or past " +
      s"${config.maxBttTriangles}: ${config.maxBttTriangles})"
  )

  // 0x24: STAT_VIS_COUNT
  val REG_STAT_VIS = busif.newRegAt(address = 0x24, doc = "Visible Triangle Counter")
  val STAT_VIS = REG_STAT_VIS.field(UInt(32 bits), RO, doc = "Total visible triangles encountered in current tile")
  STAT_VIS := statVisCount

  // 0x28: STAT_CMD_COUNT
  val REG_STAT_CMD = busif.newRegAt(address = 0x28, doc = "DataMover Commands Issued Counter")
  val STAT_CMD = REG_STAT_CMD.field(UInt(32 bits), RO, doc = "Total DataMover command packets sent")
  STAT_CMD := statCmdCount

  // 0x2C: STAT_STS_COUNT
  val REG_STAT_STS = busif.newRegAt(address = 0x2c, doc = "DataMover Status Received Counter")
  val STAT_STS = REG_STAT_STS.field(UInt(32 bits), RO, doc = "Total DataMover status responses received")
  STAT_STS := statStsCount

  // 0x30: DM_LAST_STS
  val REG_DM_LAST = busif.newRegAt(address = 0x30, doc = "Last DataMover Status Byte")
  val DM_LAST_STS = REG_DM_LAST.field(Bits(8 bits), RO, doc = "Last received raw status byte from DataMover")
  DM_LAST_STS := dmLastStsReg

  // 0x34: PERF_CYCLES
  val REG_PERF = busif.newRegAt(address = 0x34, doc = "Performance Cycle Counter")
  val PERF_CYCLES = REG_PERF.field(UInt(32 bits), RO, doc = "Elapsed clock cycles during active tile scan")
  PERF_CYCLES := cycleCounter

  // 0x38: TILE_COUNT
  val REG_TILE_COUNT = busif.newRegAt(address = 0x38, doc = "Tiles in the frame")
  val TILE_COUNT = REG_TILE_COUNT.field(
    UInt(config.tileCountWidth bits),
    RW,
    resetValue = config.maxTiles,
    doc = s"Tiles in the frame (1..${config.maxTiles}), the visibility buffer's interleave: with AUTO_ADV_EN, the " +
      "done of tile TILE_COUNT - 1 sets FRAME_DONE and TILE_INDEX back to 0"
  )

  // 0x40 - 0x58: stall counters, cycles summed over tiles and frames until CTRL.CNT_CLEAR (they wrap),
  // and the commands issued
  val counterBase = 0x40
  val counterDefs = Seq(
    "CNT_BUSY" -> "Busy on a tile",
    "CNT_VB_WAIT" -> "Scanning, nothing to scan and no visibility beat coming in",
    "CNT_CMD_WAIT" -> "A command, the DataMover's queue full",
    "CNT_RETIRE_WAIT" -> "All commands out, their triangles still on their way",
    "CNT_TRI_STARVED" -> "Triangles in flight, no beat from the DataMover",
    "CNT_TRI_BACKPRESSURE" -> "A triangle the core does not take",
    "CNT_CMDS" -> "DataMover commands issued"
  )
  val cntValue = UInt(32 bits) // the counter at the bus's read address
  for (((name, doc), i) <- counterDefs.zipWithIndex) {
    val reg = busif.newRegAt(address = counterBase + 4 * i, doc = doc)(SymbolName(s"REG_$name"))
    reg.field(UInt(32 bits), RO, doc = doc)(SymbolName(name)) := cntValue
  }

  // ===========================================================================
  // INTERRUPT FACTORY REGISTERS (0x70 - 0x7C)
  // RegGroup RFMS4:
  //   0x70: INTR_INT_RAW    - Raw interrupt event flags (W1C: write 1 to clear)
  //   0x74: INTR_INT_FORCE  - Software debug force (W1S: write 1 to trigger raw)
  //   0x78: INTR_INT_MASK   - Mask register (RW: 1 = masked/off, 0 = unmasked/open)
  //   0x7C: INTR_INT_STATUS - Masked status register (RO: raw && !mask)
  // Fields:
  //   Bit 0: done           - Tile scan & command generation complete
  //   Bit 1: error          - AXI read error or DataMover status error
  //   Bit 2: frame_done     - The frame's last tile completed (Auto-Advance wrap at TILE_COUNT)
  // ===========================================================================
  val intrDone = False
  val intrError = False
  val intrFrameDone = False

  val INTR = busif.newIntrRFMS4(addr = 0x70, doc = "DMA Interrupt Controller")
  val irqDoneStat =
    INTR.fieldAt(0, intrDone, maskRstVal = 0, doc = "Tile done interrupt (1: unmasked/open)")(SymbolName("done"))
  val irqErrorStat =
    INTR.fieldAt(1, intrError, maskRstVal = 0, doc = "Error interrupt (1: unmasked/open)")(SymbolName("error"))
  val irqFrameDoneStat = if (config.useAutoAdvance) {
    INTR.fieldAt(2, intrFrameDone, maskRstVal = 0, doc = "Frame done interrupt (1: unmasked/open)")(
      SymbolName("frame_done")
    )
  } else null

  val irqMerged = INTR.intr()

  // Built-in Documentation & C Header Generators
  busif.accept(HtmlGenerator("axi_visibility_dma_regmap", "AXI_VISIBILITY_DMA"))
  busif.accept(CHeaderGenerator("axi_visibility_dma_regmap", "AXI_VISIBILITY_DMA"))
  busif.accept(JsonGenerator("axi_visibility_dma_regmap"))

  // Base addresses truncated by alignment (zeros implicitly appended)
  val fullVbPage = UInt(config.addressWidth - config.chunkShift bits)
  if (config.addressWidth > 32) {
    fullVbPage := (VB_BASE_HIGH @@ VB_BASE_LOW).resized
  } else {
    fullVbPage := VB_BASE_LOW.resized
  }

  val fullTriWordAddr = UInt(config.triWordAddrWidth bits)
  if (config.addressWidth > 32) {
    fullTriWordAddr := (TRI_BASE_HIGH @@ TRI_BASE_LOW).resized
  } else {
    fullTriWordAddr := TRI_BASE_LOW.resized
  }

  // From TRI_COUNT, set before START: the tile's last beat and chunk, its last chunk's length, and
  // the triangles of the last beat (0: all of it)
  val triCountZero = RegNext(TRI_COUNT === 0) init (True)
  val lastBeatIndex = RegNext(
    ((TRI_COUNT.resize(config.triIndexWidth) - 1) >> log2Up(config.trianglesPerBeat)).resize(config.beatIndexWidth)
  )
  val lastChunk = (lastBeatIndex >> log2Up(config.chunkBeats)).resize(config.chunkIndexWidth)
  val lastChunkBeats = lastBeatIndex(log2Up(config.chunkBeats) - 1 downto 0) // less 1
  val tailTriangles = TRI_COUNT(log2Up(config.trianglesPerBeat) - 1 downto 0)

  // Discrete status & interrupt outputs
  val rawBits = INTR.RAW.readBits
  io.ready := !dmaBusy
  io.irq := irqMerged
  io.irq_done := rawBits(0)
  io.irq_error := rawBits(1)
  io.irq_frame_done := (if (config.useAutoAdvance) rawBits(2) else False)

  when(IRQ_ENABLE && (intrDone || intrError || intrFrameDone)) {
    IRQ_STATUS := True
  }

  when(dmaBusy) {
    cycleCounter := cycleCounter + 1
  }

  // ===========================================================================
  // 2. VISIBILITY READS (aclk domain)
  // A tile's chunks, a burst each, TILE_COUNT pages apart: nothing to multiply, no boundary to
  // cross. AR leaves from flops, and its ready goes no further than two.
  // ===========================================================================
  val arValid = RegInit(False)
  val arPage = Reg(UInt(config.addressWidth - config.chunkShift bits)) init (0)
  val arLen = Reg(UInt(log2Up(config.chunkBeats) bits)) init (0)
  val arChunk = Reg(UInt(config.chunkIndexWidth bits)) init (0)
  val arFinal = RegInit(False) // the next chunk is the tile's last
  val arPending = RegInit(False)
  val arFired = RegNext(io.m_axi_vb.ar.fire) init (False)
  val arStop = SOFT_RESET || draining
  val outstandingReads = Reg(UInt(log2Up(config.maxOutstandingReads + 1) bits)) init (0)

  io.m_axi_vb.ar.valid := arValid
  io.m_axi_vb.ar.addr := arPage @@ U(0, config.chunkShift bits)
  io.m_axi_vb.ar.len := arLen.resized
  io.m_axi_vb.ar.size := U(config.axiBeatShift, 3 bits)
  io.m_axi_vb.ar.burst := Axi4.burst.INCR
  io.m_axi_vb.ar.id := 0
  if (config.getAxi4ReadConfig.useRegion) io.m_axi_vb.ar.region.clearAll()
  if (config.getAxi4ReadConfig.useLock) io.m_axi_vb.ar.lock.clearAll()
  if (config.getAxi4ReadConfig.useCache) io.m_axi_vb.ar.cache := B"0011"
  if (config.getAxi4ReadConfig.useProt) io.m_axi_vb.ar.prot.clearAll()
  if (config.getAxi4ReadConfig.useQos) io.m_axi_vb.ar.qos.clearAll()

  when(io.m_axi_vb.ar.ready) { arValid := False }
  when(arFired) {
    arPage := arPage + TILE_COUNT.resized
    arChunk := arChunk + 1
    arFinal := arChunk + 1 === lastChunk
    arPending := !arFinal
  }
  when(arPending && !arValid && !arFired && !arStop && outstandingReads =/= config.maxOutstandingReads) {
    arValid := True
    arLen := arFinal ? lastChunkBeats | U(config.chunkBeats - 1).resized
  }
  when(arStop) { arPending := False }

  // ===========================================================================
  // 3. EDGES (aclk domain)
  // Free running from the pins, R's ready falling before vbFifo can fill. A beat turns into its
  // edges: a run is what lies between two, so a beat with none, empty or inside a run, ends here,
  // a beat a clock. That is nearly all of them; the rest wait in vbFifo for the scan.
  // ===========================================================================
  val rReady = RegInit(False)
  io.m_axi_vb.r.ready := rReady
  val rValid = RegNext(io.m_axi_vb.r.fire) init (False)
  val rData = RegNext(io.m_axi_vb.r.data)
  val rLast = RegNext(io.m_axi_vb.r.last)
  val rResp = RegNext(io.m_axi_vb.r.resp)

  when(arFired && !(rValid && rLast)) {
    outstandingReads := outstandingReads + 1
  }.elsewhen(!arFired && (rValid && rLast)) {
    outstandingReads := outstandingReads - 1
  }

  when(rValid) {
    when(rResp === Axi4.resp.SLVERR || rResp === Axi4.resp.DECERR) {
      axiReadError := True
      ERROR := True
      intrError := True
    }
  }

  val rIndex = Reg(UInt(config.beatIndexWidth bits)) init (0)
  val rLastBit = RegInit(False) // of the previous beat
  when(rValid) {
    rIndex := rIndex + 1
    rLastBit := rData.msb
  }

  val rBeat = VisBeat(config)
  rBeat.edges := rData ^ (rData(config.trianglesPerBeat - 2 downto 0) ## rLastBit)
  val rGroups = rBeat.edges.subdivideIn(config.edgeGroupBits bits)
  for (i <- 0 until config.edgeGroups) rBeat.groups(i) := rGroups(i).orR
  rBeat.index := rIndex
  rBeat.last := rIndex === lastBeatIndex

  val edgesValid = RegNext(rValid && !draining) init (False)
  val edgesBeat = RegNext(rBeat)
  val edgesAny = RegNext(rBeat.groups.orR)

  // The tile's last beat goes in without an edge too: its end is what closes a last run
  val vbFifo = StreamFifo(VisBeat(config), config.vbFifoDepth, forFMax = true)
  vbFifo.io.flush := draining
  vbFifo.io.push.valid := edgesValid && (edgesAny || edgesBeat.last)
  vbFifo.io.push.payload := edgesBeat
  rReady := draining || vbFifo.io.availability > config.vbFifoMargin

  // ===========================================================================
  // 4. COMPACT COMMAND STREAM & CONFIGURABLE CLOCK FIFO
  // Stores only (triWordAddr, triCount, tag) in the FIFO.
  // ===========================================================================
  val cmdStreamInternal = Stream(DataMoverCmdCompact(config))

  val cmdStreamOut = if (isDualClock) {
    val cc = StreamFifoCC(
      dataType = DataMoverCmdCompact(config),
      depth = config.cmdFifoDepth,
      pushClock = clockDomain,
      popClock = dmClock
    )
    cc.io.push <> cmdStreamInternal
    cc.io.pop
  } else {
    val sync = StreamFifo(
      dataType = DataMoverCmdCompact(config),
      depth = config.cmdFifoDepth,
      forFMax = true
    )
    sync.io.push <> cmdStreamInternal
    sync.io.pop
  }

  // Constant multiply via shift-and-add (keeps small constants like 3 out of DSPs)
  def mulConst(x: UInt, c: Int): UInt = {
    val width = x.getWidth + log2Up(c + 1)
    (0 until log2Up(c + 1))
      .filter(b => ((c >> b) & 1) == 1)
      .map(b => (x.resize(width) << b).resize(width))
      .reduce(_ + _)
  }

  // Format AMD/Xilinx DataMover MM2S command packet at output port (dmClock domain)
  val dmArea = new ClockingArea(dmClock) {
    // Flops both ways: half a command a clock is far more than the DataMover takes
    val cmd = cmdStreamOut.halfPipe()
    val cmdPayload = Bits(config.cmdWidth bits)
    cmdPayload := 0

    // BTT bytes: triCount * triUnits << triAlignShift = triCount * triangleSizeBytes
    val bttBytes = (cmd.payload.bttUnits @@ U(0, config.triAlignShift bits)).resize(config.bttWidth)
    cmdPayload(config.bttWidth - 1 downto 0) := bttBytes.asBits

    // [23] Type: 1 = INCR burst
    cmdPayload(23) := True
    // [29:24] DSA, [30] EOF and [31] DRR stay 0: no Data Realignment Engine. SADDR is the exact
    // triangle address; with 96 B triangles, runs starting on an odd triangle begin 32 B into a
    // 64 B beat (consumer realigns)

    // Reconstruct full byte address: (triWordAddr << triAlignShift)
    val startByteAddr = cmd.payload.triWordAddr @@ U(0, config.triAlignShift bits)
    if (config.addressWidth <= 32) {
      // [63:32] SADDR: 32-bit Starting Address
      cmdPayload(63 downto 32) := startByteAddr.resize(32).asBits
    } else {
      // [32+addrWidth-1 : 32] SADDR: 64-bit Starting Address
      cmdPayload(32 + config.addressWidth - 1 downto 32) := startByteAddr.asBits
    }

    // TAG, past SADDR: echo tag
    cmdPayload(config.cmdWidth - 5 downto config.cmdWidth - 8) := cmd.payload.tag

    io.m_axis_datamover_cmd.valid := cmd.valid
    io.m_axis_datamover_cmd.payload := cmdPayload
    cmd.ready := io.m_axis_datamover_cmd.ready
  }

  // ===========================================================================
  // 5. STATUS STREAM & IN-FLIGHT RETIREMENT TRACKER
  // Crosses status beats back from dmClock to aclk and checks for errors.
  // ===========================================================================
  val stsStreamInternal = if (isDualClock) {
    val ccSts = StreamFifoCC(
      dataType = Bits(config.stsWidth bits),
      depth = config.stsFifoDepth,
      pushClock = dmClock,
      popClock = clockDomain
    )
    ccSts.io.push <> io.s_axis_datamover_sts
    ccSts.io.pop
  } else {
    val syncSts = StreamFifo(
      dataType = Bits(config.stsWidth bits),
      depth = config.stsFifoDepth
    )
    syncSts.io.push <> io.s_axis_datamover_sts
    syncSts.io.pop
  }

  // Always accept status beats to prevent deadlocking downstream DataMover
  stsStreamInternal.ready := True

  when(stsStreamInternal.fire) {
    val stsByte = stsStreamInternal.payload(7 downto 0)
    dmLastStsReg := stsByte
    statStsCount := statStsCount + 1

    // Xilinx DataMover MM2S Status decoding:
    // sts[7] = OKAY (1 = transfer completed successfully)
    // sts[6] = SLVERR
    // sts[5] = DECERR
    // sts[4] = INTERR
    val isOkay = stsByte(7)
    val hasError = !isOkay || stsByte(6 downto 4) =/= 0
    when(hasError) {
      dmErrorFlag := True
      ERROR := True
      intrError := True
    }
  }

  // ===========================================================================
  // 6. VISIBILITY SCAN: EDGES TO RUNS TO COMMANDS (aclk domain)
  //
  //   vbFifo -> beat -> group -> window -> edge -> run -> address -> commands
  //
  // A beat's groups with an edge, lowest first, then a group's edges: an edge a clock, two to a
  // run. Each loop is a few bits long, where one over a whole beat would be a 128-bit carry chain.
  // Runs are measured from their edges, so a beat inside a run costs nothing here.
  // ===========================================================================
  object FilterState extends SpinalEnum {
    val IDLE, FILTER_STREAM, WAIT_RETIRE, ADVANCE_TILE, DRAIN = newElement()
  }
  val filterState = RegInit(FilterState.IDLE)

  val tagCounter = Reg(UInt(4 bits)) init (0)

  // Shadowed at START: BTT_LIMIT, 0 and past the BTT's reach the hardware's maximum
  val maxBttTriangles = U(config.maxBttTriangles, config.bttTriCountWidth bits)
  val bttLimit = (BTT_LIMIT_TRI === 0 || BTT_LIMIT_TRI > maxBttTriangles) ? maxBttTriangles | BTT_LIMIT_TRI
  val shadowMaxTriangles = Reg(UInt(config.bttTriCountWidth bits)) init (config.defaultBttLimit)
  val shadowMaxUnits = RegNext(mulConst(shadowMaxTriangles, config.triUnits).resize(config.triWordAddrWidth))

  // The beat, until its edges are out
  val beatValid = RegInit(False)
  val beat = Reg(VisBeat(config))
  vbFifo.io.pop.ready := !beatValid
  when(vbFifo.io.pop.fire) {
    beatValid := True
    beat := vbFifo.io.pop.payload
  }

  // Its next group with an edge
  val groupFirst = OHMasking.first(beat.groups)
  val group = Stream(UInt(log2Up(config.edgeGroups) bits))
  group.valid := beatValid && beat.groups =/= 0
  group.payload := OHToUInt(groupFirst)
  when(group.fire) { beat.groups := beat.groups & ~groupFirst }
  val groupStage = group.m2sPipe(flush = draining)

  // The group's edges. In the last beat, those past TRI_COUNT are dropped: their bits mean nothing
  val window = Reg(Bits(config.edgeGroupBits bits)) init (0)
  val windowGroup = Reg(UInt(log2Up(config.edgeGroups) bits)) init (0)
  val windowEmpty = window === 0
  val beatGroups = beat.edges.subdivideIn(config.edgeGroupBits bits)

  val tailGroup = tailTriangles(tailTriangles.high downto log2Up(config.edgeGroupBits))
  val tailBit = tailTriangles(log2Up(config.edgeGroupBits) - 1 downto 0)
  val keepAll = !beat.last || tailTriangles === 0 || groupStage.payload < tailGroup
  val keepSome = groupStage.payload === tailGroup
  val tailKeep = ~(B(config.edgeGroupBits bits, default -> True) |<< tailBit)
  val windowKeep = Bits(config.edgeGroupBits bits)
  for (i <- 0 until config.edgeGroupBits) windowKeep(i) := keepAll || (keepSome && tailKeep(i))

  groupStage.ready := windowEmpty
  when(groupStage.fire) {
    window := beatGroups(groupStage.payload) & windowKeep
    windowGroup := groupStage.payload
  }

  // An edge, or once the last beat is done the end of the tile's bits, at TRI_COUNT
  val beatDone = RegInit(False)
  beatDone := beatValid && beat.groups === 0 && !groupStage.valid && windowEmpty

  val windowFirst = OHMasking.first(window)
  val edge = Stream(VisEdge(config))
  edge.valid := !windowEmpty || (beatDone && beat.last)
  edge.payload.end := windowEmpty
  edge.payload.triangle := windowEmpty ? TRI_COUNT.resize(config.triIndexWidth) |
    (beat.index @@ windowGroup @@ OHToUInt(windowFirst))
  when(edge.fire && !windowEmpty) { window := window & ~windowFirst }
  when(beatDone && (!beat.last || edge.ready)) {
    beatValid := False
    beatDone := False
  }
  val edgeStage = edge.m2sPipe(flush = draining)

  // Edges in pairs: a run, its length and where it starts
  val runOpen = RegInit(False)
  val runStart = Reg(UInt(config.triIndexWidth bits)) init (0)
  val scanEnded = RegInit(False)

  val run = Stream(VisRun(config))
  run.valid := edgeStage.valid && runOpen
  run.payload.length := edgeStage.payload.triangle - runStart
  run.payload.offset := mulConst(runStart, config.triUnits).resized
  edgeStage.ready := !runOpen || run.ready
  when(edgeStage.fire) {
    runOpen := !runOpen && !edgeStage.payload.end
    when(!runOpen) { runStart := edgeStage.payload.triangle }
    when(edgeStage.payload.end) { scanEnded := True }
  }
  val runStage = run.m2sPipe(flush = draining)

  when(runStage.fire) {
    statVisCount := statVisCount + runStage.payload.length.resized
  }

  val runAddress = Stream(VisRunAddress(config))
  runAddress.arbitrationFrom(runStage)
  runAddress.payload.length := runStage.payload.length
  runAddress.payload.triWordAddr := fullTriWordAddr + runStage.payload.offset
  runAddress.payload.over := runStage.payload.length > shadowMaxTriangles
  val addressStage = runAddress.m2sPipe(flush = draining)

  // Commands: a run past BTT_LIMIT leaves a limit at a time
  val cmdBusy = RegInit(False)
  val cmdCheck = RegInit(False) // what's left is back to compare
  val cmdOver = RegInit(False)
  val cmdLeft = Reg(UInt(config.triIndexWidth bits)) init (0)
  val cmdWord = Reg(UInt(config.triWordAddrWidth bits)) init (0)

  addressStage.ready := !cmdBusy
  when(addressStage.fire) {
    cmdBusy := True
    cmdOver := addressStage.payload.over
    cmdLeft := addressStage.payload.length
    cmdWord := addressStage.payload.triWordAddr
  }

  val cmdCount = cmdOver ? shadowMaxTriangles | cmdLeft.resize(config.bttTriCountWidth)
  cmdStreamInternal.valid := cmdBusy && !cmdCheck
  cmdStreamInternal.payload.triWordAddr := cmdWord
  cmdStreamInternal.payload.bttUnits := mulConst(cmdCount, config.triUnits).resized
  cmdStreamInternal.payload.tag := tagCounter.asBits

  when(cmdStreamInternal.fire) {
    statCmdCount := statCmdCount + 1
    tagCounter := tagCounter + 1
    when(cmdOver) {
      cmdCheck := True
      cmdLeft := cmdLeft - shadowMaxTriangles
      cmdWord := cmdWord + shadowMaxUnits
    }.otherwise {
      cmdBusy := False
    }
  }
  when(cmdCheck) {
    cmdCheck := False
    cmdOver := cmdLeft > shadowMaxTriangles
  }

  val runBusy = edgeStage.valid || runStage.valid || addressStage.valid || cmdBusy
  val scanBusy = vbFifo.io.pop.valid || beatValid || runBusy
  val retired = RegNext(statStsCount === statCmdCount) init (True)

  when(draining) {
    beatValid := False
    beatDone := False
    window := 0
    runOpen := False
    scanEnded := False
    cmdBusy := False
    cmdCheck := False
  }

  when(SOFT_RESET) {
    filterState := FilterState.DRAIN
    draining := True
    axiReadError := False
    dmErrorFlag := False
    statVisCount := 0
    statCmdCount := 0
    statStsCount := 0
  }.otherwise {
    switch(filterState) {
      is(FilterState.IDLE) {
        when(START && !dmaBusy) {
          dmaBusy := True
          DONE := False
          ERROR := False
          IRQ_STATUS := False
          if (config.useAutoAdvance) FRAME_DONE := False
          axiReadError := False
          dmErrorFlag := False
          cycleCounter := 0
          statVisCount := 0
          statCmdCount := 0
          statStsCount := 0
          tagCounter := 0
          shadowMaxTriangles := bttLimit
          rIndex := 0
          rLastBit := False
          scanEnded := False

          when(triCountZero) {
            filterState := FilterState.ADVANCE_TILE
          }.otherwise {
            arPage := fullVbPage + TILE_INDEX.resized
            arChunk := 0
            arFinal := lastChunk === 0
            arPending := True
            filterState := FilterState.FILTER_STREAM
          }
        }
      }

      is(FilterState.FILTER_STREAM) {
        when(scanEnded && !runBusy) {
          filterState := FilterState.WAIT_RETIRE
        }
      }

      // Wait until all issued DataMover commands have been acknowledged via status stream
      is(FilterState.WAIT_RETIRE) {
        when(retired) {
          filterState := FilterState.ADVANCE_TILE
        }
      }

      // Transfer complete: advance tile index and signal completion
      is(FilterState.ADVANCE_TILE) {
        dmaBusy := False
        DONE := True
        intrDone := True

        when(IRQ_ENABLE) {
          IRQ_STATUS := True
        }

        if (config.useAutoAdvance) {
          when(AUTO_ADV_EN) {
            // The last tile, or past it (TILE_COUNT lowered, or 0)
            when(TILE_INDEX.resize(config.tileCountWidth bits) + 1 >= TILE_COUNT) {
              TILE_INDEX := 0
              FRAME_DONE := True
              intrFrameDone := True
            }.otherwise {
              TILE_INDEX := TILE_INDEX + 1
            }
          }
        }

        filterState := FilterState.IDLE
      }

      // After SOFT_RESET: the reads in flight still answer
      is(FilterState.DRAIN) {
        when(!arValid && !arFired && outstandingReads === 0 && !rValid) {
          dmaBusy := False
          draining := False
          filterState := FilterState.IDLE
        }
      }
    }
  }

  // ===========================================================================
  // 7. STALL COUNTERS: 8 bits each in fabric, the upper 24 in a LUTRAM (a carry a clock), as the
  // L2's performance counters
  // ===========================================================================
  val stall = new Area {
    val events = Seq(
      dmaBusy,
      filterState === FilterState.FILTER_STREAM && !rValid && !edgesValid && !scanBusy,
      cmdStreamInternal.valid && !cmdStreamInternal.ready,
      filterState === FilterState.WAIT_RETIRE,
      !retired && !io.tri_stream_valid, // commands out without their status
      io.core_stall,
      cmdStreamInternal.fire
    ).map(event => RegNext(event) init (False))
    val K = events.size
    val idxBits = log2Up(K)
    val low = Vec.fill(K)(Reg(UInt(8 bits)) init (0))
    val carry = Vec.fill(K)(RegInit(False))
    val upper = Mem(UInt(24 bits), 1 << idxBits)
    upper.addAttribute("ram_style", "distributed")

    // One index walks the counters, a counter a clock: zeroing the RAM, then taking carries. It is
    // back before a counter carries again (256 clocks at the soonest)
    val clearing = RegInit(True)
    val scanIdx = Reg(UInt(idxBits bits)) init (0)
    val scanLast = scanIdx === K - 1
    scanIdx := Mux(scanLast, U(0, idxBits bits), scanIdx + 1)
    when(clearing && scanLast) { clearing := False }
    when(CNT_CLEAR) {
      clearing := True
      scanIdx := 0
    }

    val p1Valid = RegNext(!clearing && carry(scanIdx)) init (False)
    val p1Idx = RegNext(scanIdx)
    val p2Valid = RegNext(p1Valid && !clearing) init (False)
    val p2Idx = RegNext(p1Idx)
    val p2Upper = RegNext(upper.readAsync(p1Idx))
    val p3Valid = RegNext(p2Valid && !clearing) init (False)
    val p3Idx = RegNext(p2Idx)
    val p3Upper = Reg(UInt(24 bits)) init (0)
    p3Upper := p2Upper + 1
    when(CNT_CLEAR || clearing) { p3Upper := 0 }
    upper.write(
      address = Mux(clearing, scanIdx, p3Idx),
      data = p3Upper,
      enable = clearing || p3Valid
    )
    for (i <- 0 until K) {
      val sum = low(i).resize(9) + events(i).asUInt.resize(9)
      when(clearing) {
        low(i) := 0
        carry(i) := False
      } otherwise {
        low(i) := sum(7 downto 0)
        carry(i) := (carry(i) && scanIdx =/= i) || sum(8)
      }
    }

    // A counter register read: its RAM word and low byte, at the bus address. Exact a few clocks
    // after the DMA stops, once its last carries are in
    val rdIdx = busif.readAddress()(idxBits + 1 downto 2)
    cntValue := upper.readAsync(rdIdx) @@ low(rdIdx)
  }
}

// =============================================================================
// Verilog RTL Generation Entry Point
// =============================================================================
object AxiVisibilityDmaVerilog {
  def main(args: Array[String]): Unit = {
    val config = AxiVisibilityDmaConfig(
      addressWidth = 32,
      axiDataWidth = 128, // 128-bit AXI Read Master: 128 triangles a clock
      bttWidth = 19, // Configurable up to 23 bits
      defaultBttLimit = 4096,
      maxTiles = 64,
      triangleSizeBytes = 96,
      maxOutstandingReads = 8,
      cmdFifoDepth = 64,
      stsFifoDepth = 4,
      vbFifoDepth = 512,
      useAutoAdvance = true
    )

    SpinalConfig(
      targetDirectory = "rtl/AxiVisibilityDma",
      defaultConfigForClockDomains = ClockDomainConfig(resetActiveLevel = LOW)
    ).withPrivateNamespace.generateVerilog(
      new AxiVisibilityDma(
        config = config,
        dmClockDomain = null
      )
    )
  }
}
