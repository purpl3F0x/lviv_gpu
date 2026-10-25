package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._

object APBFrontendRegs {
  val byteCount = 32 // APB window: 8 words
}

// The frontend's status and the tile's box: its first and last pixel on each axis, written with
// each tile (by the CPU or the command processor) and taken by the frontend as they are.
class APBFrontendRegs(res_width: Int = 12, tile_size: Int = 128) extends Component {
  require(res_width >= 1 && res_width <= 16)
  require(tile_size >= 1 && tile_size <= (1 << res_width))

  val io = new Bundle {
    val apb_clock = in Bool ()
    val apb_resetn = in Bool ()
    val thread_clk = in Bool ()
    val thread_resetn = in Bool ()
    val s_apb = slave(Apb3(Apb3Config(addressWidth = log2Up(APBFrontendRegs.byteCount), dataWidth = 32)))
    val thread_empty = in Bool ()
    val orchestrator_empty = in Bool ()
    val input_fifo_idle = in Bool ()
    val thread_sw_reset = out Bool ()
    val bb_min_x = out UInt (res_width bits)
    val bb_min_y = out UInt (res_width bits)
    val bb_max_x = out UInt (res_width bits)
    val bb_max_y = out UInt (res_width bits)
  }

  noIoPrefix()

  val apbClockDomain = ClockDomain(
    clock = io.apb_clock,
    reset = io.apb_resetn,
    config = ClockDomainConfig(resetActiveLevel = LOW, resetKind = SYNC)
  )
  val threadClockDomain = ClockDomain(
    clock = io.thread_clk,
    reset = io.thread_resetn,
    config = ClockDomainConfig(resetActiveLevel = LOW, resetKind = SYNC)
  )

  // Reset: tile 0's box
  val bbMinReset = 0
  val bbMaxReset = tile_size - 1

  val apbArea = new ClockingArea(apbClockDomain) {
    val busif = Apb3BusInterface(io.s_apb, (0x0000, APBFrontendRegs.byteCount), "FRONTEND")

    // 0x00: empty status and thread reset command
    val REG_STATUS = busif.newRegAt(address = 0x00, doc = "Front-End Status and Control")
    val EMPTY = REG_STATUS.field(Bool(), RO, doc = "Thread input buffer empty status")
    val ORCHESTRATOR_EMPTY = REG_STATUS.field(Bool(), RO, doc = "Orchestrator input buffer empty status")
    val INPUT_FIFO_IDLE = REG_STATUS.field(Bool(), RO, doc = "Input FIFO idle status")
    val RESET = REG_STATUS.fieldAt(pos = 31, Bool(), W1P, doc = "Write 1 to issue a thread reset pulse")
    EMPTY := BufferCC(io.thread_empty, init = False)
    ORCHESTRATOR_EMPTY := BufferCC(io.orchestrator_empty, init = False)
    INPUT_FIFO_IDLE := BufferCC(io.input_fifo_idle, init = False)

    // 0x04 - 0x10: the tile's box, in pixels. A write goes to the frontend's clock as a stream.
    def boxEdge(address: Int, name: String, doc: String, resetValue: Int) = {
      val reg = busif.newRegAt(address = address, doc = doc)(SymbolName(s"REG_$name"))
      reg.field(UInt(res_width bits), RW, resetValue = resetValue, doc = doc)(SymbolName(name))
      reg.reserved((32 - res_width) bits)
      val stream = Stream(UInt(res_width bits))
      stream.valid := reg.hitDoWrite
      stream.payload := busif.writeData(res_width - 1 downto 0).asUInt
      stream
    }
    val bbMinXWrite = boxEdge(0x04, "BB_MIN_X", "First pixel x of the tile's box", bbMinReset)
    val bbMinYWrite = boxEdge(0x08, "BB_MIN_Y", "First pixel y of the tile's box", bbMinReset)
    val bbMaxXWrite = boxEdge(
      0x0c,
      "BB_MAX_X",
      "Last pixel x of the tile's box: the tile's own, or the frame's when the tile runs past it",
      bbMaxReset
    )
    val bbMaxYWrite = boxEdge(
      0x10,
      "BB_MAX_Y",
      "Last pixel y of the tile's box: the tile's own, or the frame's when the tile runs past it",
      bbMaxReset
    )

    // Named by address, as in ApbThreadRegs: under one name the C header defines each twice.
    for (address <- 0x14 until APBFrontendRegs.byteCount by 4) {
      val reservedReg = busif.newRegAt(address = address, doc = "Reserved")(SymbolName(f"REG_RESERVED_$address%02X"))
      reservedReg.reserved(32 bits)
    }

    val resetRequest = RESET

    busif.accept(HtmlGenerator("apb_front_end_regmap", "APB_FRONT_END"))
    busif.accept(CHeaderGenerator("apb_front_end_regmap", "APB_FRONT_END"))
    busif.accept(JsonGenerator("apb_front_end_regmap"))
  }

  io.thread_sw_reset := PulseCCByToggle(apbArea.resetRequest, apbClockDomain, threadClockDomain)

  val threadArea = new ClockingArea(threadClockDomain) {
    def boxEdge(write: Stream[UInt], resetValue: Int) = {
      val read = StreamCCByToggle(write, apbClockDomain, threadClockDomain)
      val value = Reg(UInt(res_width bits)) init (resetValue)
      read.ready := True
      when(read.fire) { value := read.payload }
      value
    }
    io.bb_min_x := boxEdge(apbArea.bbMinXWrite, bbMinReset)
    io.bb_min_y := boxEdge(apbArea.bbMinYWrite, bbMinReset)
    io.bb_max_x := boxEdge(apbArea.bbMaxXWrite, bbMaxReset)
    io.bb_max_y := boxEdge(apbArea.bbMaxYWrite, bbMaxReset)
  }
}

object APBFrontendRegsVerilog extends App {
  SpinalConfig(
    targetDirectory = "rtl/APBFrontendRegs",
    defaultConfigForClockDomains = ClockDomainConfig(
      resetActiveLevel = LOW,
      resetKind = SYNC
    )
  ).withPrivateNamespace.generateVerilog(
    new APBFrontendRegs(
      res_width = log2Up(4096),
      tile_size = 128
    )
  )
}
