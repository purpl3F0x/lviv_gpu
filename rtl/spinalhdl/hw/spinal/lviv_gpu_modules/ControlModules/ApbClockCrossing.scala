package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba3.apb._

// APB from the crossbar's clock into a slave's own (the DMAs, whose registers run on aclk with
// their engines): SpinalHDL's Apb3CC. An access crosses by toggle, held in flops on its way, and its
// response comes back the same way: a few cycles of each clock per access, PREADY low meanwhile.
class ApbClockCrossing(addressWidth: Int = 7) extends Component {
  val apbConfig = Apb3Config(addressWidth = addressWidth, dataWidth = 32, useSlaveError = true)

  val io = new Bundle {
    val s_clk = in Bool ()
    val s_resetn = in Bool ()
    val s_apb = slave(Apb3(apbConfig)) // s_clk: from the crossbar
    val m_clk = in Bool ()
    val m_resetn = in Bool ()
    val m_apb = master(Apb3(apbConfig)) // m_clk: to the slave
  }

  noIoPrefix()

  def clock(clk: Bool, resetn: Bool) =
    ClockDomain(clk, resetn, config = ClockDomainConfig(resetActiveLevel = LOW, resetKind = SYNC))

  val cc = Apb3CC(apbConfig, clock(io.s_clk, io.s_resetn), clock(io.m_clk, io.m_resetn))
  cc.io.input <> io.s_apb
  cc.io.output <> io.m_apb
}

object ApbClockCrossingVerilog extends App {
  SpinalConfig(targetDirectory = "rtl/ApbClockCrossing").withPrivateNamespace
    .generateVerilog(new ApbClockCrossing())
}
