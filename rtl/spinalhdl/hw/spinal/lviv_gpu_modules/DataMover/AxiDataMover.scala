package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba4.axi._

// =============================================================================
// AxiDataMover: the triangle DMA, in place of AMD's AXI DataMover (PG022, MM2S)
// =============================================================================
// Commands in the DataMover's 72-bit format, AXI4 reads with up to maxOutstanding bursts in flight,
// the beats out as read (no DRE: TKEEP marks a command's bytes in its first and last beats), and
// one status byte a command, in order, once its last beat has left. A burst is only requested
// with room for all of it, so RREADY never falls. Single clock, no S2MM, 32-bit addresses.
case class AxiDataMoverConfig(
    addressWidth: Int = 32,
    dataWidth: Int = 512,
    bttWidth: Int = 23, // the command's BTT bits used
    maxBurstBeats: Int = 16,
    maxOutstanding: Int = 32, // AR bursts in flight: the FIFO's 512 beats in 16-beat bursts
    fifoBeats: Int = 512, // the data FIFO: BRAM
    cmdQueueDepth: Int = 64, // commands accepted but not yet retired
    stsQueueDepth: Int = 4
) {
  require(addressWidth == 32, "PG022's 72-bit command: 32-bit addresses")
  require(isPow2(dataWidth) && dataWidth >= 64, "dataWidth must be a power of 2, at least 64")
  require(bttWidth >= 8 && bttWidth <= 23, "bttWidth must be 8 to 23 bits")
  val beatBytes: Int = dataWidth / 8
  val beatShift: Int = log2Up(beatBytes)
  val pageBeats: Int = 4096 / beatBytes
  require(isPow2(maxBurstBeats) && maxBurstBeats >= 2 && maxBurstBeats <= pageBeats, "maxBurstBeats: a power of 2 up to a 4 KiB page")
  require(isPow2(fifoBeats) && fifoBeats >= 2 * maxBurstBeats, "fifoBeats: a power of 2, at least two bursts")
  require(isPow2(cmdQueueDepth) && cmdQueueDepth >= 4, "cmdQueueDepth: a power of 2, at least 4")
  require(isPow2(stsQueueDepth) && stsQueueDepth >= 4, "stsQueueDepth: a power of 2, at least 4")
  require(maxOutstanding >= 1)

  val lenWidth: Int = log2Up(maxBurstBeats) // AXI len (beats - 1) of a burst
  val pageWidth: Int = log2Up(pageBeats)
  val sumWidth: Int = bttWidth + 1 // lead + BTT - 1
  val beatIndexWidth: Int = sumWidth - beatShift // a command's last beat index
  val cmdWidth: Int = 72
  val stsWidth: Int = 8

  def axiConfig: Axi4Config = Axi4Config(
    addressWidth = addressWidth,
    dataWidth = dataWidth,
    useId = false,
    useRegion = false,
    useBurst = true,
    useLock = false,
    useCache = true,
    useSize = true,
    useQos = false,
    useLen = true,
    useLast = true,
    useResp = true,
    useProt = true,
    useStrb = false,
    arUserWidth = 4
  )
}

// A command as the output stage needs it
case class DataMoverCmdEntry(c: AxiDataMoverConfig) extends Bundle {
  val lead = UInt(c.beatShift bits) // bytes before the command in its first beat
  val tail = UInt(c.beatShift bits) // bytes of the command in its last beat; 0: all
  val lastBeat = UInt(c.beatIndexWidth bits)
  val tag = Bits(4 bits)
  val eof = Bool()
  val zero = Bool() // nothing to read: INTERR
}

case class DataMoverBeat(c: AxiDataMoverConfig) extends Bundle {
  val data = Bits(c.dataWidth bits)
  val keep = Bits(c.beatBytes bits)
  val last = Bool()
}

class AxiDataMover(val config: AxiDataMoverConfig = AxiDataMoverConfig()) extends Component {
  import config._

  val io = new Bundle {
    val s_cmd = slave(Stream(Bits(cmdWidth bits)))
    val m_sts = master(Stream(Bits(stsWidth bits)))
    val m_axi = master(Axi4ReadOnly(axiConfig))
    val m_axi_arid = out Bits (4 bits)
    val m_axis = master(Stream(DataMoverBeat(config)))
    val mm2s_err = out Bool () // sticky: a status with an error
    val idle = out Bool () // nothing queued, in flight, buffered or awaiting status
  }

  noIoPrefix()

  // Vivado's AXI4 memory-mapped port names
  def renameAxiForVivado(bundle: Bundle, prefix: String): Unit = {
    bundle.flatten.foreach { signal =>
      val cleanName = signal
        .getName()
        .replaceFirst("^io_", "")
        .replace(s"${prefix}_", "")
        .replace("_payload_", "")
        .replace("_payload", "")
        .replace("_", "")
      signal.setName(s"${prefix}_${cleanName}")
      signal.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:aximm:1.0 $prefix ${cleanName.toUpperCase}")
    }
  }

  // Vivado's AXI4-Stream port names: a Bundle payload's fields are its T signals
  def renameAxisForVivado[T <: Data](stream: Stream[T], prefix: String): Unit = {
    stream.valid.setName(s"${prefix}_tvalid")
    stream.ready.setName(s"${prefix}_tready")
    stream.payload match {
      case b: Bundle => for ((name, e) <- b.elements) e.setName(s"${prefix}_t$name")
      case p         => p.setName(s"${prefix}_tdata")
    }
    for (e <- stream.flatten) {
      val suffix = e.getName().stripPrefix(prefix + "_").toUpperCase
      e.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:axis:1.0 $prefix $suffix")
    }
  }

  renameAxiForVivado(io.m_axi, "m_axi")
  io.m_axi_arid.addAttribute("X_INTERFACE_INFO", "xilinx.com:interface:aximm:1.0 m_axi ARID")
  io.m_axi.ar.valid.addAttribute(
    "X_INTERFACE_PARAMETER",
    s"NUM_READ_OUTSTANDING $maxOutstanding, READ_WRITE_MODE READ_ONLY"
  )
  renameAxisForVivado(io.s_cmd, "s_cmd")
  renameAxisForVivado(io.m_sts, "m_sts")
  renameAxisForVivado(io.m_axis, "m_axis")

  clockDomain.clock.setName("aclk")
  clockDomain.reset.setName("aresetn")
  clockDomain.clock.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:clock:1.0 aclk CLK")
  clockDomain.clock.addAttribute(
    "X_INTERFACE_PARAMETER",
    "ASSOCIATED_BUSIF m_axi:s_cmd:m_sts:m_axis, ASSOCIATED_RESET aresetn"
  )
  clockDomain.reset.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:reset:1.0 aresetn RST")
  clockDomain.reset.addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")

  // ===========================================================================
  // Intake: one command decoded at a time, queued for the output, loaded into the splitter
  // ===========================================================================
  val cmd = io.s_cmd.halfPipe() // the producer's own rate
  val cmdBtt = cmd.payload(bttWidth - 1 downto 0).asUInt
  val cmdIncr = cmd.payload(23)
  val cmdEof = cmd.payload(30)
  val cmdAddr = cmd.payload(63 downto 32).asUInt
  val cmdTag = cmd.payload(67 downto 64)
  val cmdLead = cmdAddr(beatShift - 1 downto 0)
  val cmdSum = cmdLead.resize(sumWidth) + cmdBtt.resize(sumWidth) - 1 // the last byte's offset

  val entry = DataMoverCmdEntry(config)
  entry.lead := cmdLead
  entry.tail := (cmdLead + cmdBtt(beatShift - 1 downto 0)).resize(beatShift)
  entry.lastBeat := cmdSum(sumWidth - 1 downto beatShift)
  entry.tag := cmdTag
  entry.eof := cmdEof
  entry.zero := cmdBtt === 0 || !cmdIncr

  val queue = StreamFifo(DataMoverCmdEntry(config), cmdQueueDepth)
  val sts = StreamFifo(Bits(stsWidth bits), stsQueueDepth)

  // ===========================================================================
  // Splitter: a command's bursts, each within maxBurstBeats and its 4 KiB page
  // ===========================================================================
  val sp = new Area {
    val busy = Reg(Bool()) init False
    val addr = Reg(UInt(addressWidth - beatShift bits)) // the next burst's beat
    val left = Reg(UInt(beatIndexWidth bits)) // beats left, minus one
    val arValid = Reg(Bool()) init False
    val arAddr = Reg(UInt(addressWidth - beatShift bits))
    val arLen = Reg(UInt(lenWidth bits))
    val free = Reg(UInt(log2Up(fifoBeats + 1) bits)) init fifoBeats // FIFO beats not reserved
    val outstanding = Reg(UInt(log2Up(maxOutstanding + 1) bits)) init 0

    // The burst, minus one: to the command's end, the page's end, or maxBurstBeats
    val page = ~addr(pageWidth - 1 downto 0)
    val capLeft = Mux(left(beatIndexWidth - 1 downto lenWidth) =/= 0, U(maxBurstBeats - 1, lenWidth bits), left(lenWidth - 1 downto 0))
    val capPage =
      if (pageWidth > lenWidth) Mux(page(pageWidth - 1 downto lenWidth) =/= 0, U(maxBurstBeats - 1, lenWidth bits), page(lenWidth - 1 downto 0))
      else page
    val len = Mux(capPage < capLeft, capPage, capLeft)
    val lastBurst = left(beatIndexWidth - 1 downto lenWidth) === 0 && left(lenWidth - 1 downto 0) === len
    val issue = busy && !arValid && free >= maxBurstBeats && outstanding =/= maxOutstanding

    val load = cmd.fire && !entry.zero
    when(load) {
      busy := True
      addr := cmdAddr(addressWidth - 1 downto beatShift)
      left := entry.lastBeat
    }
    when(issue) {
      arValid := True
      arAddr := addr
      arLen := len
      addr := addr + len + 1
      left := left - len - 1
      busy := !lastBurst
    }
    when(io.m_axi.ar.fire) {
      arValid := False
    }
  }

  cmd.ready := queue.io.push.ready && !sp.busy
  queue.io.push.valid := cmd.valid && !sp.busy
  queue.io.push.payload := entry

  val ar = io.m_axi.ar
  ar.valid := sp.arValid
  ar.addr := (sp.arAddr @@ U(0, beatShift bits)).resized
  ar.len := sp.arLen.resized
  ar.size := U(beatShift, 3 bits)
  ar.setBurstINCR()
  ar.cache := B"0011"
  ar.prot := B"000"
  ar.user := B(0, 4 bits)
  io.m_axi_arid := B(0, 4 bits)

  // ===========================================================================
  // Data FIFO: R straight into BRAM, the read latch and the BRAM's output register the two
  // stages to the stream
  // ===========================================================================
  val ram = Mem(Bits(dataWidth + 2 bits), fifoBeats)
  ram.addAttribute("ram_style", "block")
  val r = io.m_axi.r
  r.ready := True
  val wrPtr = Reg(UInt(log2Up(fifoBeats) bits)) init 0
  val rdPtr = Reg(UInt(log2Up(fifoBeats) bits)) init 0
  val occ = Reg(UInt(log2Up(fifoBeats + 1) bits)) init 0 // beats written, not yet read out
  val notEmpty = Reg(Bool()) init False
  ram.write(wrPtr, r.resp ## r.data, enable = r.valid)
  when(r.valid) {
    wrPtr := wrPtr + 1
  }

  val os = new Area {
    val aValid = Reg(Bool()) init False // the read latch holds a beat
    val bValid = Reg(Bool()) init False // the output register holds one
    val count = Reg(UInt(beatIndexWidth bits)) init 0 // of the command's beats, the one in the latch
    val first = Reg(Bool()) init True
    val head = queue.io.pop
    val stsRoom = sts.io.availability >= 2 // this beat's status, and one leaving the output register
    val bEn = !bValid || io.m_axis.ready
    val lastA = count === head.lastBeat
    val move = aValid && head.valid && !head.zero && (!lastA || stsRoom) && bEn
    val rdEn = notEmpty && (!aValid || move)
    val aWord = ram.readSync(rdPtr, enable = rdEn)
    when(rdEn) {
      rdPtr := rdPtr + 1
    }
    when(rdEn) {
      aValid := True
    } elsewhen (move) {
      aValid := False
    }
    when(move) {
      count := Mux(lastA, U(0), count + 1)
      first := lastA
    }

    // TKEEP: the bytes from lead in the first beat, up to tail in the last
    val keepA = Bits(beatBytes bits)
    for (i <- 0 until beatBytes) {
      val top = i == beatBytes - 1 // the last byte: always from lead, never before tail
      val fromLead = if (top) True else U(i, beatShift bits) >= head.lead
      val toTail = if (top) head.tail === 0 else head.tail === 0 || U(i, beatShift bits) < head.tail
      keepA(i) := (!first || fromLead) && (!lastA || toTail)
    }

    val bData = RegNextWhen(aWord(dataWidth - 1 downto 0), bEn)
    val bResp = RegNextWhen(aWord(dataWidth + 1 downto dataWidth), bEn)
    val bKeep = RegNextWhen(keepA, bEn)
    val bLast = RegNextWhen(lastA, bEn)
    val bEof = RegNextWhen(head.eof && lastA, bEn)
    val bTag = RegNextWhen(head.tag, bEn)
    when(bEn) {
      bValid := move
    }
    io.m_axis.valid := bValid
    io.m_axis.data := bData
    io.m_axis.keep := bKeep
    io.m_axis.last := bEof

    // Status: the command's errors, on its last beat; a zero command's INTERR after the one before it
    val bFire = bValid && io.m_axis.ready
    val slv = Reg(Bool()) init False
    val dec = Reg(Bool()) init False
    val beatSlv = bResp === B"10"
    val beatDec = bResp === B"11"
    val cmdSlv = slv || beatSlv
    val cmdDec = dec || beatDec
    when(bFire) {
      slv := cmdSlv && !bLast
      dec := cmdDec && !bLast
    }
    val dataPush = bFire && bLast
    val zeroPush = head.valid && head.zero && !(bValid && bLast) && sts.io.push.ready
    head.ready := (move && lastA) || zeroPush
    sts.io.push.valid := dataPush || zeroPush
    sts.io.push.payload := Mux(
      dataPush,
      (!(cmdSlv || cmdDec)) ## cmdSlv ## cmdDec ## False ## bTag,
      B"0001" ## head.tag
    )
  }

  // The data FIFO's occupancy and the credits: a slot is free once its beat is in the latch
  val popped = RegNext(os.rdEn) init False
  occ := occ + U(r.valid) - U(os.rdEn)
  notEmpty := (occ + U(r.valid) - U(os.rdEn)) =/= 0
  sp.free := sp.free + U(popped) - Mux(sp.issue, sp.len +^ 1, U(0, lenWidth + 1 bits))
  sp.outstanding := sp.outstanding + U(sp.issue) - U(r.valid && r.last)

  io.m_sts << sts.io.pop

  val err = Reg(Bool()) init False
  when(sts.io.push.fire && sts.io.push.payload(6 downto 4) =/= 0) {
    err := True
  }
  io.mm2s_err := err

  io.idle := RegNext(
    !cmd.valid && !sp.busy && !sp.arValid && sp.outstanding === 0 && occ === 0 && !os.aValid && !os.bValid &&
      queue.io.occupancy === 0 && sts.io.occupancy === 0
  ) init False
}

// =============================================================================
// Verilog RTL Generation Entry Point
// =============================================================================
object AxiDataMoverVerilog {
  def main(args: Array[String]): Unit = {
    val config = AxiDataMoverConfig(maxBurstBeats = args.headOption.map(_.toInt).getOrElse(16))
    SpinalConfig(
      targetDirectory = "rtl/AxiDataMover",
      defaultConfigForClockDomains = ClockDomainConfig(resetKind = SYNC, resetActiveLevel = LOW)
    ).withPrivateNamespace.generateVerilog(new AxiDataMover(config))
  }
}
