package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba3.apb._

// Chain of `stages` fully registered slices; 0 stages is a passthrough.
case class Apb3RegSlice(config: Apb3Config, stages: Int = 1) extends Component {
  require(stages >= 0)
  val io = new Bundle {
    val s = slave(Apb3(config))
    val m = master(Apb3(config))
  }

  val stageInsts = Array.fill(stages)(Apb3RegSliceStage(config))
  val last = stageInsts.foldLeft(io.s) { (up, st) => up >> st.io.s; st.io.m }
  last >> io.m
}

// One fully registered APB3 stage; adds 2 cycles of latency per transfer.
case class Apb3RegSliceStage(config: Apb3Config) extends Component {
  val io = new Bundle {
    val s = slave(Apb3(config))
    val m = master(Apb3(config))
  }

  val paddr = Reg(UInt(config.addressWidth bits))
  val pwdata = Reg(Bits(config.dataWidth bits))
  val pwrite = Reg(Bool())
  val prdata = Reg(Bits(config.dataWidth bits)) init (0)
  val pslverr = RegInit(False)
  val psel = RegInit(False)
  val penable = RegInit(False)
  val pready = RegInit(False)

  io.m.PADDR := paddr
  io.m.PWDATA := pwdata
  io.m.PWRITE := pwrite
  io.m.PSEL := psel.asBits.resized
  io.m.PENABLE := penable

  io.s.PREADY := pready
  io.s.PRDATA := prdata
  if (config.useSlaveError) io.s.PSLVERROR := pslverr

  pready := False

  when(!psel && !pready && io.s.PSEL(0) && !io.s.PENABLE) {
    psel := True
    paddr := io.s.PADDR
    pwdata := io.s.PWDATA
    pwrite := io.s.PWRITE
  }

  when(psel && !penable) {
    penable := True
  }

  when(psel && penable && io.m.PREADY) {
    psel := False
    penable := False
    pready := True
    prdata := io.m.PRDATA
    if (config.useSlaveError) pslverr := io.m.PSLVERROR
  }
}
