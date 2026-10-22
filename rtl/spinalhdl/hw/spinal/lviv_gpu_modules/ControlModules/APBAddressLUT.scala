package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.misc.SizeMapping

object ApbLutRam {
  val baseEntryBits = 32 // Texture base address entry width
  val sizeEntryBits = 4 // Texture size entry width (low bits of a 32-bit word)

  // APB window: texture base table followed by texture size table, one 32-bit word per entry
  def tableBytes(wordCount: Int): Int = wordCount * 4
  def baseRegion(wordCount: Int): SizeMapping = SizeMapping(0, tableBytes(wordCount))
  def sizeRegion(wordCount: Int): SizeMapping = SizeMapping(tableBytes(wordCount), tableBytes(wordCount))
  def byteCount(wordCount: Int): Int = 2 * tableBytes(wordCount)
}

class ApbLutRam(portCount: Int = 4, wordCount: Int = 128) extends Component {
  require(isPow2(wordCount), "wordCount must be a power of 2")
  val baseRegion = ApbLutRam.baseRegion(wordCount)
  val sizeRegion = ApbLutRam.sizeRegion(wordCount)
  val totalWords = wordCount * 2
  val byteCount = ApbLutRam.byteCount(wordCount)

  val s_apb = slave(Apb3(Apb3Config(addressWidth = log2Up(byteCount), dataWidth = 32)))

  val lut = Vec.fill(portCount) {
    new Bundle {
      val data_addr = in UInt (log2Up(wordCount) bits)
      val base = out Bits (ApbLutRam.baseEntryBits bits)
      val size = out Bits (ApbLutRam.sizeEntryBits bits)
    }
  }

  val baseRams = Array.fill(portCount)(Mem(Bits(ApbLutRam.baseEntryBits bits), wordCount))
  val sizeRams = Array.fill(portCount)(Mem(Bits(ApbLutRam.sizeEntryBits bits), wordCount))
  for (i <- 0 until portCount) {
    baseRams(i).setTechnology(distributedLut)
    sizeRams(i).setTechnology(distributedLut)
  }

  val baseHit = baseRegion.hit(s_apb.PADDR)
  val sizeHit = sizeRegion.hit(s_apb.PADDR)
  val apbWordAddr = (s_apb.PADDR >> 2).resize(log2Up(wordCount) bits)

  val apbWrite =
    s_apb.PSEL(0) &&
      s_apb.PENABLE &&
      s_apb.PWRITE &&
      !ClockDomain.current.isResetActive

  for (i <- 0 until portCount) {
    baseRams(i).write(
      enable = apbWrite && baseHit,
      address = apbWordAddr,
      data = s_apb.PWDATA
    )

    sizeRams(i).write(
      enable = apbWrite && sizeHit,
      address = apbWordAddr,
      data = s_apb.PWDATA(ApbLutRam.sizeEntryBits - 1 downto 0)
    )
  }

  for (i <- 0 until portCount) {
    lut(i).base := baseRams(i).readAsync(lut(i).data_addr)
    lut(i).size := sizeRams(i).readAsync(lut(i).data_addr)
  }

  // APB read: same word-index, returning base or size depending on the selected region.
  val baseReadData = baseRams(0).readAsync(apbWordAddr).resize(32 bits)
  val sizeReadData = sizeRams(0).readAsync(apbWordAddr).resize(32 bits)
  val apbReadData = Mux(baseHit, baseReadData, sizeReadData)

  s_apb.PREADY := True
  s_apb.PSLVERROR := False
  s_apb.PRDATA := apbReadData
}

// Generate Verilog
object ApbLutRamVerilog extends App {
  SpinalConfig(
    targetDirectory = "rtl/ApbLutRam",
    defaultConfigForClockDomains = ClockDomainConfig(
      resetActiveLevel = LOW,
      resetKind = SYNC
    )
  ).withPrivateNamespace.generateVerilog(new ApbLutRam())
}
