package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._

object APBFrontendRegs {
  val byteCount = 32 // APB window: 8 words
}

class APBFrontendRegs(tile_x_width: Int = 5, tile_y_width: Int = 5) extends Component {
  require(tile_x_width >= 1 && tile_x_width <= 32)
  require(tile_y_width >= 1 && tile_y_width <= 32)

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
    val tile_x_index = out UInt (tile_x_width bits)
    val tile_y_index = out UInt (tile_y_width bits)
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

    // 0x04: Tile X index
    val REG_TILE_X = busif.newRegAt(address = 0x04, doc = "Tile X Index")
    val TILE_X = REG_TILE_X.field(UInt(tile_x_width bits), RW, resetValue = 0, doc = "Tile X index")
    if (tile_x_width < 32) REG_TILE_X.reserved((32 - tile_x_width) bits)
    val tileXWriteStream = Stream(UInt(tile_x_width bits))
    tileXWriteStream.valid := REG_TILE_X.hitDoWrite
    tileXWriteStream.payload := busif.writeData(tile_x_width - 1 downto 0).asUInt

    // 0x08: Tile Y index
    val REG_TILE_Y = busif.newRegAt(address = 0x08, doc = "Tile Y Index")
    val TILE_Y = REG_TILE_Y.field(UInt(tile_y_width bits), RW, resetValue = 0, doc = "Tile Y index")
    if (tile_y_width < 32) REG_TILE_Y.reserved((32 - tile_y_width) bits)
    val tileYWriteStream = Stream(UInt(tile_y_width bits))
    tileYWriteStream.valid := REG_TILE_Y.hitDoWrite
    tileYWriteStream.payload := busif.writeData(tile_y_width - 1 downto 0).asUInt

    // Named by address, as in ApbThreadRegs: under one name the C header defines each twice.
    for (address <- 0x0c until APBFrontendRegs.byteCount by 4) {
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
    val tileXReadStream = StreamCCByToggle(apbArea.tileXWriteStream, apbClockDomain, threadClockDomain)
    val tileYReadStream = StreamCCByToggle(apbArea.tileYWriteStream, apbClockDomain, threadClockDomain)
    val tileXIndex = Reg(UInt(tile_x_width bits)) init (0)
    val tileYIndex = Reg(UInt(tile_y_width bits)) init (0)

    tileXReadStream.ready := True
    tileYReadStream.ready := True
    when(tileXReadStream.fire) { tileXIndex := tileXReadStream.payload }
    when(tileYReadStream.fire) { tileYIndex := tileYReadStream.payload }

    io.tile_x_index := tileXIndex
    io.tile_y_index := tileYIndex
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
      tile_x_width = log2Up(4096 / 128),
      tile_y_width = log2Up(4096 / 128)
    )
  )
}
