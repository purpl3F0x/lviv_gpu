package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.amba4.axilite._
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._

// =============================================================================
// L2 texture cache: N read-only 128-bit slaves (the threads' L1 texture caches, one 256 B block
// a request, one request at a time each), one read-only 512-bit master to DDR. Data in URAM,
// tags in BRAM, all on core_clk (the slaves') but the master's side (mem_clk) and the register
// port (axil_clk: AXI-Lite, the CPU's alone); or, onMemClock, all on mem_clk but the slaves' side.
// Read-only: nothing is ever dirty, an eviction drops the line, a flush invalidates every line.
//
//   s_axi_tex[n] -> arbiter (round robin; ports asking for the same block join the granted one)
//     -> tag sequencer, one operation at a time: lookup, fill done, flush sweep
//          hit:        a job reads the block (4 x 512) and writes it to every joined port
//          in flight:  the ports join the line's MSHR (before its first beat), or wait for it
//          miss:       an MSHR, a victim way (LRU, skipping ways being filled), an AR to DDR
//     -> DDR beats into the data RAM; a block's last in, a job reads it to the MSHR's ports
//     -> per port: a block's 4 words, out as 16 x 128 with RLAST
//
// Performance counters: 8-bit counters in fabric, their carries added into a RAM
// =============================================================================
case class L2CacheConfig(
    ports: Int = 4,
    cachedAddressWidth: Int = 27, // byte address bits
    slaveAddressWidth: Int = 32,
    masterAddressWidth: Int = 32,
    totalBytes: Int = 1 << 20,
    lineBytes: Int = 512,
    ways: Int = 2,
    onMemClock: Boolean = false, // the cache on mem_clk, the slaves crossing from core_clk
    dataReadLatency: Int = 4, // URAM readSync + pipeline registers
    cdcDepth: Int = 32 // DDR read data crossing (LUTRAM depth)
) {
  require(ports >= 1 && ports <= 8, "ports must be 1 to 8")
  require(ways >= 2 && ways <= 4, "ways must be 2 to 4")
  require(
    lineBytes == 256 || lineBytes == 512 || lineBytes == 1024,
    "lineBytes must be 256, 512 or 1024"
  )
  require(
    totalBytes % (lineBytes * ways) == 0 && isPow2(totalBytes / (lineBytes * ways)),
    "totalBytes must be lineBytes x ways x a power of 2 (the sets)"
  )
  require(dataReadLatency >= 1, "dataReadLatency must be at least 1")
  require(
    cdcDepth >= 8 && isPow2(cdcDepth),
    "cdcDepth must be a power of 2 >= 8"
  )

  val slaveBytes = 16
  val masterBytes = 64
  val blockBytes = 256 // an L1 line: one 8x8 block of 32-bit texels
  val blockBeats = blockBytes / masterBytes // 4 x 512
  val slaveBeats = blockBytes / slaveBytes // 16 x 128
  val lineBeats = lineBytes / masterBytes
  val blocksPerLine = lineBytes / blockBytes
  val blkBits = log2Up(blocksPerLine) // block within a line (0 for 256 B lines)
  val beatBits = log2Up(lineBeats)
  val offsetBits = log2Up(lineBytes)
  val lines = totalBytes / lineBytes
  val sets = lines / ways
  val setBits = log2Up(sets)
  val wayBits = log2Up(ways)
  val tagBits = cachedAddressWidth - offsetBits - setBits
  require(tagBits >= 1, "cachedAddressWidth leaves no tag bits")
  val blockAddrBits = cachedAddressWidth - log2Up(blockBytes)
  val lineAddrBits = cachedAddressWidth - offsetBits
  val dataWords = totalBytes / masterBytes
  val dataAddrBits = log2Up(dataWords)
  // Lines in flight: a port has its block from the first half of a line while the rest comes in,
  // and may ask for another
  val mshrs = 2 * ports
  val mshrBits = log2Up(mshrs) max 1
  val lruBits = ways * (ways - 1) / 2 // a bit per pair of ways

  def slaveConfig = Axi4Config(
    addressWidth = slaveAddressWidth,
    dataWidth = slaveBytes * 8,
    useId = false,
    useRegion = false,
    useLock = false,
    useCache = false,
    useProt = false,
    useQos = false
  )

  def masterConfig = Axi4Config(
    addressWidth = masterAddressWidth,
    dataWidth = masterBytes * 8,
    idWidth = mshrBits,
    useRegion = false,
    useLock = false,
    useCache = false,
    useProt = false,
    useQos = false
  )
}

object L2CacheSeq extends SpinalEnum {
  val IDLE, READ, WAIT, DECIDE, ACT, FILL, SWEEP = newElement()
}

object L2Cache {
  // Registers: control at 0x00, the counters' word pairs from counterBase
  // CYCLES (counter 0, 40 bits) as _LO and _HI at counterBase, then a word for each other counter
  // (32 bits)
  val counterBase = 0x40
  def counterAddress(i: Int): Int = if (i == 0) counterBase else counterBase + 4 + 4 * i
  def regBytes(c: L2CacheConfig): Int = 1 << log2Up(counterAddress(counters(c).size))

  // The performance counters, by index: (name, description)
  def counters(c: L2CacheConfig): Seq[(String, String)] =
    Seq(
      "cycles" -> "Clocks counted (not frozen)",
      "lookups" -> "Tag lookups (one per granted request, joined ports included)",
      "hits" -> "Lookups that hit",
      "misses" -> "Lookups that allocated a line (a DDR read)",
      "merges" -> "Lookups that joined a line already being read from DDR",
      "replays" -> "Lookups retried: their line mid-fill, or every way of the set being filled",
      "set_full" -> "Replays because every way of the set was being filled",
      "multicast" -> "Requests served by another port's lookup (same block, same time)",
      "evictions" -> "Valid lines replaced",
      "ddr_reads" -> "Line reads issued to DDR",
      "ddr_errors" -> "DDR beats with an error response",
      "mshr_full" -> "Replays because every MSHR was in use"
    ) ++ (0 until c.ports).flatMap(p =>
      Seq(
        s"port${p}_requests" -> s"Port $p: requests",
        s"port${p}_hits" -> s"Port $p: requests that hit",
        s"port${p}_misses" -> s"Port $p: requests that allocated a line",
        s"port${p}_merges" -> s"Port $p: requests that joined a line in flight",
        s"port${p}_replays" -> s"Port $p: lookups retried"
      )
    )
}

case class L2HitJob(c: L2CacheConfig) extends Bundle {
  val word = UInt(c.dataAddrBits bits) // the block's first 512-bit word
  val mask = Bits(c.ports bits) // the ports it goes to
  val resp = Bits(2 bits)
}

case class L2DdrAr(c: L2CacheConfig) extends Bundle {
  val line = UInt(c.lineAddrBits bits)
  val id = UInt(c.mshrBits bits)
}

case class L2DdrR(c: L2CacheConfig) extends Bundle {
  val data = Bits(c.masterBytes * 8 bits)
  val id = UInt(c.mshrBits bits)
  val resp = Bits(2 bits)
  val last = Bool()
}

case class L2Word(c: L2CacheConfig) extends Bundle {
  val data = Bits(c.masterBytes * 8 bits)
  val resp = Bits(2 bits)
}

// The cache runs on the component's clock: core_clk, or (onMemClock) mem_clk; the other clock is
// otherClockDomain (mem_clk or core_clk)
class L2Cache(val c: L2CacheConfig, otherClockDomain: ClockDomain = null, axilClockDomain: ClockDomain = null)
    extends Component {
  val otherClock =
    if (otherClockDomain != null) otherClockDomain
    else ClockDomain.external(if (c.onMemClock) "core" else "mem", withReset = true)
  val slaveClock = if (c.onMemClock) otherClock else ClockDomain.current
  val memClock = if (c.onMemClock) ClockDomain.current else otherClock
  val axilClock = if (axilClockDomain != null) axilClockDomain else ClockDomain.external("axil", withReset = true)
  val axilConfig = AxiLite4Config(addressWidth = log2Up(L2Cache.regBytes(c)), dataWidth = 32)

  val io = new Bundle {
    val s_axil = slave(AxiLite4(axilConfig)) // axil_clk
    val s_axi = Vec.fill(c.ports)(slave(Axi4ReadOnly(c.slaveConfig)))
    val m_axi = master(Axi4ReadOnly(c.masterConfig)) // mem_clk
  }
  noIoPrefix()

  def renameAxi(bundle: Bundle, prefix: String): Unit =
    bundle.flatten.foreach { s =>
      val clean = s
        .getName()
        .replaceFirst("^io_", "")
        .replaceFirst("^[a-z_0-9]*?_(ar|r)_", "$1_")
        .replace("_payload_", "")
        .replace("_payload", "")
        .replace("_", "")
      s.setName(s"${prefix}_$clean")
    }
  for (p <- 0 until c.ports) renameAxi(io.s_axi(p), s"s_axi_$p")
  renameAxi(io.m_axi, "m_axi")
  AxiLite4SpecRenamer(io.s_axil)
  // For a block design: the master's limits (Vivado would assume 2 reads outstanding, bursts of
  // up to 256 and narrow ones, and size the interconnect for those)
  for (s <- io.m_axi.flatten)
    s.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:aximm:1.0 m_axi ${s.getName().stripPrefix("m_axi_").toUpperCase}")
  io.m_axi.ar.addr.addAttribute(
    "X_INTERFACE_PARAMETER",
    s"NUM_READ_OUTSTANDING ${c.mshrs}, MAX_BURST_LENGTH ${c.lineBeats}, SUPPORTS_NARROW_BURST 0"
  )

  slaveClock.clock.setName("core_clk")
  slaveClock.reset.setName("core_resetn")
  memClock.clock.setName("mem_clk")
  memClock.reset.setName("mem_resetn")
  axilClock.clock.setName("axil_clk")
  axilClock.reset.setName("axil_resetn")

  // For a block design: the buses each clock and reset go with
  def busClock(cd: ClockDomain, clk: String, rst: String, busIfs: String): Unit = {
    cd.readClockWire
      .setName(clk)
      .addAttribute("X_INTERFACE_INFO", s"xilinx.com:signal:clock:1.0 $clk CLK")
      .addAttribute("X_INTERFACE_PARAMETER", s"ASSOCIATED_BUSIF $busIfs, ASSOCIATED_RESET $rst")
    cd.readResetWire
      .setName(rst)
      .addAttribute("X_INTERFACE_INFO", s"xilinx.com:signal:reset:1.0 $rst RST")
      .addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")
  }
  busClock(slaveClock, "core_clk", "core_resetn", (0 until c.ports).map(p => s"s_axi_$p").mkString(":"))
  busClock(memClock, "mem_clk", "mem_resetn", "m_axi")
  busClock(axilClock, "axil_clk", "axil_resetn", "s_axil")

  val N = c.ports
  val counterDefs = L2Cache.counters(c)
  val K = counterDefs.size
  val cnt = counterDefs.map(_._1).zipWithIndex.toMap
  val inc = Vec.fill(K)(UInt(log2Up(N) max 1 bits)) // multicast's, N - 1, the most
  inc.foreach { i => i.allowOverride(); i := 0 }
  def count(name: String, n: UInt): Unit = inc(cnt(name)) := n.resized
  def count(name: String, b: Bool): Unit = inc(cnt(name)) := b.asUInt.resized

  def setOf(line: UInt): UInt = line(c.setBits - 1 downto 0)
  def tagOf(line: UInt): UInt = line(c.lineAddrBits - 1 downto c.setBits)
  def lineOf(block: UInt): UInt = (block >> c.blkBits).resize(c.lineAddrBits)
  def blkOf(block: UInt): UInt =
    if (c.blkBits == 0) U(0, 1 bits) else block(c.blkBits - 1 downto 0)

  // LRU, a bit per pair of ways i < j (1: i used before j): the oldest way not excluded (one-hot,
  // none if all are), and the bits after an access to a way
  def lruBit(i: Int, j: Int): Int = (0 until i).map(c.ways - 1 - _).sum + j - i - 1
  def lruOlder(bits: Bits, i: Int, j: Int): Bool = if (i < j) bits(lruBit(i, j)) else !bits(lruBit(j, i))
  def lruVictim(bits: Bits, excluded: Bits): Bits =
    Vec((0 until c.ways).map { w =>
      !excluded(w) && (0 until c.ways).filter(_ != w).map(v => excluded(v) || lruOlder(bits, w, v)).reduce(_ && _)
    }).asBits
  def lruTouch(bits: Bits, way: UInt): Bits = {
    val r = CombInit(bits)
    for (i <- 0 until c.ways; j <- i + 1 until c.ways) {
      when(way === i) { r(lruBit(i, j)) := False }
      when(way === j) { r(lruBit(i, j)) := True }
    }
    r
  }

  // ===========================================================================
  // Registers
  // ===========================================================================
  // The registers on the cache's clock with what they count and control; AXI-Lite crosses from
  // axil_clk to them, each channel by toggle (an access a few clocks of each)
  val axil = AxiLite4(axilConfig)
  axil.aw << StreamCCByToggle(io.s_axil.aw, axilClock, ClockDomain.current)
  axil.w << StreamCCByToggle(io.s_axil.w, axilClock, ClockDomain.current)
  axil.ar << StreamCCByToggle(io.s_axil.ar, axilClock, ClockDomain.current)
  io.s_axil.b << StreamCCByToggle(axil.b, ClockDomain.current, axilClock)
  io.s_axil.r << StreamCCByToggle(axil.r, ClockDomain.current, axilClock)
  val busif = AxiLite4BusInterface(axil, (0x0000, L2Cache.regBytes(c)), "L2_CACHE")

  val REG_CTRL = busif.newRegAt(address = 0x00, doc = "Control")
  val FLUSH = REG_CTRL.field(
    Bool(),
    RO,
    doc = "Write 1 to flush the cache (read-only: every line invalidated); reads 1 until done"
  )
  REG_CTRL.reserved(31 bits)
  val flushPulse = RegNext(REG_CTRL.hitDoWrite && busif.writeData(0)) init (False)

  val REG_INFO = busif.newRegAt(address = 0x04, doc = "Configuration")
  val WAYS = REG_INFO.field(UInt(4 bits), RO, doc = "Ways")
  val LINE_LOG2 =
    REG_INFO.field(UInt(4 bits), RO, doc = "log2 of the line size in bytes")
  val PORTS = REG_INFO.field(UInt(4 bits), RO, doc = "Slave ports")
  REG_INFO.reserved(4 bits)
  val SIZE_KIB = REG_INFO.field(UInt(16 bits), RO, doc = "Size in KiB")
  WAYS := c.ways
  LINE_LOG2 := c.offsetBits
  PORTS := N
  SIZE_KIB := c.totalBytes / 1024

  val REG_CNT_CTRL = busif.newRegAt(address = 0x08, doc = "Performance counter control")
  val CNT_FREEZE = REG_CNT_CTRL.field(Bool(), RW, resetValue = 0, doc = "1: every counter holds")
  val CNT_CLEAR = REG_CNT_CTRL.field(Bool(), RO, doc = "Write 1 to zero every counter; reads 1 until done")
  val CNT_PENDING = REG_CNT_CTRL.field(
    Bool(),
    RO,
    doc = "1 while a carry is on its way to the counter RAM: a counter read then may be 256 short"
  )
  REG_CNT_CTRL.reserved(29 bits)
  val clearPulse = RegNext(REG_CNT_CTRL.hitDoWrite && busif.writeData(1)) init (False)

  val REG_CNT_COUNT = busif.newRegAt(address = 0x0c, doc = "Performance counters")
  val CNT_COUNT = REG_CNT_COUNT.field(UInt(8 bits), RO, doc = "Number of counters")
  REG_CNT_COUNT.reserved(24 bits)
  CNT_COUNT := K

  // The counters (L2Cache.counterAddress): CYCLES_LO and CYCLES_HI, then <NAME>. A read takes the
  // counter at the address as it is: exact while it is still (the GPU idle, or FREEZE) and
  // CNT_PENDING is 0
  val cntLo = UInt(32 bits)
  val cntHi = UInt(8 bits)
  for (((name, doc), i) <- counterDefs.zipWithIndex) {
    val n = name.toUpperCase
    val address = L2Cache.counterAddress(i)
    if (i == 0) {
      val lo = busif.newRegAt(address = address, doc = s"$doc, bits 31-0")(SymbolName(s"REG_${n}_LO"))
      lo.field(UInt(32 bits), RO, doc = "Counter bits 31-0")(SymbolName(s"${n}_LO")) := cntLo
      val hi = busif.newRegAt(address = address + 4, doc = s"$doc, bits 39-32")(SymbolName(s"REG_${n}_HI"))
      hi.field(UInt(8 bits), RO, doc = "Counter bits 39-32")(SymbolName(s"${n}_HI")) := cntHi
      hi.reserved(24 bits)
    } else {
      val r = busif.newRegAt(address = address, doc = doc)(SymbolName(s"REG_$n"))
      r.field(UInt(32 bits), RO, doc = "Counter")(SymbolName(n)) := cntLo
    }
  }

  busif.accept(HtmlGenerator("l2_cache_regmap", "L2_CACHE"))
  busif.accept(CHeaderGenerator("l2_cache_regmap", "L2_CACHE"))
  busif.accept(JsonGenerator("l2_cache_regmap"))

  // ===========================================================================
  // Memories
  // ===========================================================================
  // Per way {valid, tag}; LRU bits per set; the data, way-major: {way, set, beat}
  val tagMem = Seq.fill(c.ways)(Mem(Bits(c.tagBits + 1 bits), c.sets))
  tagMem.foreach(_.addAttribute("ram_style", "block"))
  val lruMem = Mem(Bits(c.lruBits bits), c.sets)
  val dataMem = Mem(Bits(c.masterBytes * 8 bits), c.dataWords)
  dataMem.addAttribute("ram_style", "ultra")

  def dataAddr(way: UInt, set: UInt, beat: UInt): UInt =
    (if (c.wayBits > 0) way.resize(c.wayBits) @@ set @@ beat else set @@ beat)
      .resize(c.dataAddrBits)

  // ===========================================================================
  // DDR master (its AR and R cross into mem_clk, unless the cache is on it)
  // ===========================================================================
  val ddrAr = Stream(L2DdrAr(c)) // one an MSHR: the queue always has room
  val arCc = !c.onMemClock generate StreamFifoCC(
    L2DdrAr(c),
    c.mshrs max 8,
    pushClock = ClockDomain.current,
    popClock = memClock
  )
  val arQueue = c.onMemClock generate StreamFifo(L2DdrAr(c), c.mshrs max 8)
  val rCc = !c.onMemClock generate StreamFifoCC(
    L2DdrR(c),
    c.cdcDepth,
    pushClock = memClock,
    popClock = ClockDomain.current
  )
  if (c.onMemClock) arQueue.io.push << ddrAr
  else {
    arCc.ram.addAttribute("ram_style", "distributed")
    rCc.ram.addAttribute("ram_style", "distributed")
    arCc.io.push << ddrAr
  }
  val arOut = if (c.onMemClock) arQueue.io.pop else arCc.io.pop

  io.m_axi.ar.valid := arOut.valid
  io.m_axi.ar.addr := (arOut.line @@ U(0, c.offsetBits bits)).resized
  io.m_axi.ar.id := arOut.id
  io.m_axi.ar.len := c.lineBeats - 1
  io.m_axi.ar.size := log2Up(c.masterBytes)
  io.m_axi.ar.setBurstINCR()
  arOut.ready := io.m_axi.ar.ready

  val rIn = Stream(L2DdrR(c)) // mem_clk
  rIn.valid := io.m_axi.r.valid
  rIn.data := io.m_axi.r.data
  rIn.id := io.m_axi.r.id
  rIn.resp := io.m_axi.r.resp
  rIn.last := io.m_axi.r.last
  io.m_axi.r.ready := rIn.ready
  if (!c.onMemClock) rCc.io.push << rIn
  val ddrR = if (c.onMemClock) rIn else rCc.io.pop

  // ===========================================================================
  // Slave ports: one request each (onMemClock: its AR and data cross from and to core_clk)
  // ===========================================================================
  val port = for (p <- 0 until N) yield new Area {
    val busy = RegInit(False) // request taken, its last beat not yet out
    val pend = RegInit(False) // wants a lookup
    val hold = RegInit(False) // waiting for MSHR holdIdx to finish first
    val holdIdx = Reg(UInt(c.mshrBits bits)) init (0)
    val block = Reg(UInt(c.blockAddrBits bits)) init (0)
    // What an L1 asks for: a block, 16 x 128-bit INCR
    val sAr = io.s_axi(p).ar
    val arCheck = new ClockingArea(slaveClock) {
      assert(
        !sAr.fire || (sAr.len === c.slaveBeats - 1 && sAr.size === log2Up(c.slaveBytes) &&
          sAr.burst === Axi4.burst.INCR && sAr.addr(log2Up(c.blockBytes) - 1 downto 0) === 0),
        s"L2Cache: port $p AR not a 256 B block"
      )
    }
    val arBlock = sAr.translateWith(sAr.addr(c.cachedAddressWidth - 1 downto log2Up(c.blockBytes)))
    val ar = if (c.onMemClock) StreamCCByToggle(arBlock, slaveClock, ClockDomain.current) else arBlock
    ar.ready := !busy
    when(ar.fire) {
      busy := True
      pend := True
      block := ar.payload
    }
    val eligible = pend && !hold

    // The block's 4 words in, from the data reads (a register's outputs), 16 beats out
    val push = Bool()
    val pushData = Bits(c.masterBytes * 8 bits)
    val pushResp = Bits(2 bits)
    val r = io.s_axi(p).r

    // Four 128-bit LUTRAM lanes of 4 words, the lowest lane first. One request a port: they always fit
    val buffer = !c.onMemClock generate new Area {
      val wrPtr = Reg(UInt(2 bits)) init (0)
      val rdWord = Reg(UInt(2 bits)) init (0)
      val sub = Reg(UInt(2 bits)) init (0)
      val words = Reg(UInt(3 bits)) init (0)
      val resp = Reg(Bits(2 bits)) init (0)
      wrPtr.addAttribute("max_fanout", "16")
      rdWord.addAttribute("max_fanout", "16")
      val laneMem = Seq.fill(4)(Mem(Bits(128 bits), c.blockBeats))
      val lanes = for ((lane, l) <- laneMem.zipWithIndex) yield {
        lane.addAttribute("ram_style", "distributed")
        lane.write(wrPtr, pushData(128 * l + 127 downto 128 * l), enable = push)
        lane.readAsync(rdWord)
      }
      when(push) {
        wrPtr := wrPtr + 1
        resp := pushResp
      }
      val out = Stream(Axi4R(c.slaveConfig))
      out.valid := words =/= 0
      out.data := Vec(lanes)(sub)
      out.resp := resp
      out.last := rdWord === c.blockBeats - 1 && sub === 3
      val wordOut = out.fire && sub === 3
      when(out.fire) { sub := sub + 1 }
      when(wordOut) { rdWord := rdWord + 1 }
      words := words + push.asUInt - wordOut.asUInt
      assert(!push || words =/= c.blockBeats, s"L2Cache: port $p buffer overflow")
      r << out.m2sPipe()
      when(r.fire && r.last) { busy := False }
    }

    // The words across to core_clk (room for a block), 4 beats each there; busy until the last
    // has left
    val crossing = c.onMemClock generate new Area {
      val words = StreamFifoCC(L2Word(c), c.blockBeats, pushClock = ClockDomain.current, popClock = slaveClock)
      words.ram.addAttribute("ram_style", "distributed")
      words.io.push.valid := push
      words.io.push.data := pushData
      words.io.push.resp := pushResp
      assert(!push || words.io.push.ready, s"L2Cache: port $p buffer overflow")
      val pushed = Reg(UInt(2 bits)) init (0)
      val allIn = RegInit(False)
      when(push) {
        pushed := pushed + 1
        when(pushed === c.blockBeats - 1) { allIn := True }
      }
      when(allIn && words.io.pushOccupancy === 0) {
        allIn := False
        busy := False
      }
      val out = new ClockingArea(slaveClock) {
        val word = words.io.pop
        val sub = Reg(UInt(2 bits)) init (0)
        val n = Reg(UInt(2 bits)) init (0) // the word of the block
        val beat = Stream(Axi4R(c.slaveConfig))
        beat.valid := word.valid
        beat.data := word.data.subdivideIn(4 slices)(sub)
        beat.resp := word.resp
        beat.last := n === c.blockBeats - 1 && sub === 3
        word.ready := beat.ready && sub === 3
        when(beat.fire) {
          sub := sub + 1
          when(sub === 3) { n := n + 1 }
        }
        r << beat.m2sPipe()
      }
    }

    count(s"port${p}_requests", ar.fire)
  }

  // ===========================================================================
  // MSHRs: lines being read from DDR
  // ===========================================================================
  val mshr = for (k <- 0 until c.mshrs) yield new Area {
    val valid = RegInit(False)
    val line = Reg(UInt(c.lineAddrBits bits)) init (0)
    val way = Reg(UInt(c.wayBits max 1 bits)) init (0)
    val mask = Reg(Bits(N bits)) init (0) // the ports waiting for it
    val beats = Reg(UInt(c.beatBits + 1 bits)) init (0)
    val err = RegInit(False) // a beat with an error response: the line is not kept
  }
  val mshrValid = Vec(mshr.map(_.valid)).asBits

  // ===========================================================================
  // Fill: DDR beats into the data RAM. A block's 4th written, a job reads the block out to the
  // ports waiting for it, as for a hit
  // ===========================================================================
  val fillDone = StreamFifo(UInt(c.mshrBits bits), c.mshrs)
  val fillJobs = StreamFifo(L2HitJob(c), 4)
  val fill = new Area {
    val in = ddrR.m2sPipe()
    in.ready := True
    val k = in.id
    val beat = Vec(mshr.map(_.beats))(k).resize(c.beatBits max 1)
    val way = Vec(mshr.map(_.way))(k)
    val line = Vec(mshr.map(_.line))(k)
    val mask = Vec(mshr.map(_.mask))(k)
    val err = Vec(mshr.map(_.err))(k) || in.resp =/= 0 // this beat's included
    dataMem.write(
      address = RegNext(dataAddr(way, setOf(line), beat.resize(c.beatBits))),
      data = RegNext(in.data),
      enable = RegNext(in.valid) init (False)
    )
    // The ports waiting for this beat's block; they leave the mask with its job
    val waiting = Bits(N bits)
    for (p <- 0 until N) {
      val sameBlock =
        if (c.blkBits == 0) True
        else blkOf(port(p).block) === (beat >> log2Up(c.blockBeats)).resized
      waiting(p) := mask(p) && sameBlock
    }
    val blockDone = in.valid && beat(1 downto 0) === c.blockBeats - 1
    for (k2 <- 0 until c.mshrs) when(in.valid && k === k2) {
      mshr(k2).beats := mshr(k2).beats + 1
      when(in.resp =/= 0) { mshr(k2).err := True }
      when(blockDone) { mshr(k2).mask := mshr(k2).mask & ~waiting }
    }
    // The job a clock later, its reads after the block's last write
    val blockFirst = beat.resize(c.beatBits) & U(c.lineBeats - c.blockBeats, c.beatBits bits)
    fillJobs.io.push.valid := RegNext(blockDone && waiting.orR) init (False)
    fillJobs.io.push.word := RegNext(dataAddr(way, setOf(line), blockFirst))
    fillJobs.io.push.mask := RegNext(waiting)
    fillJobs.io.push.resp := RegNext(Mux(err, B"10", B"00")) // SLVERR
    assert(!fillJobs.io.push.valid || fillJobs.io.push.ready, "L2Cache: fill job overflow")
    fillDone.io.push.valid := in.valid && in.last
    fillDone.io.push.payload := k
    count("ddr_errors", in.valid && in.resp =/= 0)
  }

  // ===========================================================================
  // Data reads: a job reads a block's 4 words and writes them to every port of its mask. Fill
  // jobs first: their ports are waiting already, and their FIFO must never fill
  // ===========================================================================
  val hitJobs = StreamFifo(L2HitJob(c), 2)
  val reader = new Area {
    val job = StreamArbiterFactory().lowerFirst.transactionLock.onArgs(fillJobs.io.pop, hitJobs.io.pop)
    val beat = Reg(UInt(2 bits)) init (0)
    job.ready := beat === c.blockBeats - 1
    when(job.valid) { beat := beat + 1 }
    // The read's address registered (it fans out to every URAM), then the URAM output register
    // and pipeline registers, each loading as the read enable reaches it (UG901's template, so
    // that they go into the cascade)
    val en = RegNext(job.valid) init (False)
    val addr = RegNext(job.word + beat)
    var data = dataMem.readSync(addr, enable = en)
    var load = RegNext(en)
    for (_ <- 1 until c.dataReadLatency) {
      data = RegNextWhen(data, load)
      load = RegNext(load)
    }
    val push = Vec((0 until N).map(p => Delay(job.valid && job.mask(p), c.dataReadLatency + 1, init = False)))
    val resp = Delay(job.resp, c.dataReadLatency + 1)
    // A read still to come may be of a line an allocation would replace
    val busy = job.valid || en
  }

  for (p <- 0 until N) {
    port(p).push := reader.push(p)
    port(p).pushData := reader.data
    port(p).pushResp := reader.resp
  }

  // ===========================================================================
  // Tag sequencer
  // ===========================================================================
  val seq = new Area {
    import L2CacheSeq._
    val state = Reg(L2CacheSeq()) init (SWEEP) // the tags start invalid: a sweep after reset
    val sweepSet = Reg(UInt(c.setBits bits)) init (0)
    val flushing = RegInit(True)
    when(flushPulse) { flushing := True }
    FLUSH := flushing

    // Round robin over the eligible ports
    val eligible = Vec(port.map(_.eligible)).asBits
    val lastGrant = Reg(Bits(N bits)) init (B(1 << (N - 1), N bits))
    val above = ~((lastGrant.asUInt - 1).asBits | lastGrant)
    val masked = eligible & above
    val grantOh = Mux(masked.orR, OHMasking.first(masked), OHMasking.first(eligible))

    val gIdx = Reg(UInt(log2Up(N) max 1 bits)) init (0)
    val block = Reg(UInt(c.blockAddrBits bits)) init (0)
    val mask = Reg(Bits(N bits)) init (0)
    val line = lineOf(block)
    val set = setOf(line)
    val tag = tagOf(line)
    val blk = blkOf(block)

    // Tag and LRU reads (BRAM with its output register: 2 clocks)
    val rdEn = state === READ
    val rdSet = setOf(lineOf(Vec(port.map(_.block))(gIdx)))
    val tagRd = tagMem.map(_.readSync(rdSet, enable = rdEn))
    val lruRd = lruMem.readSync(rdSet, enable = rdEn)
    val tagQ = tagRd.map(RegNext(_))
    val lruQ = RegNext(lruRd)

    // In WAIT: the lookup against the MSHRs
    val inFlight = Reg(Bits(c.mshrs bits)) init (0)
    val wayFilling = Reg(Bits(c.ways bits)) init (0)
    val fillingIdx = Reg(Vec(UInt(c.mshrBits bits), c.ways))
    // In DECIDE: the hit way, the victim, and the one thing ACT does
    val hitOh = Reg(Bits(c.ways bits)) init (0)
    val victim = Reg(UInt(c.wayBits max 1 bits)) init (0)
    val victimValid = RegInit(False)
    val lruNow = Reg(Bits(c.lruBits bits)) init (0)
    val actJoin, actHit, actSetFull, actMshrFull, actAlloc = RegInit(False)
    val readerBusy = RegNext(reader.busy) init (False) // a clock late: ACT waits a clock longer
    // A finished line (FILL), its MSHR's fields taken in IDLE
    val fillK = Reg(UInt(c.mshrBits bits)) init (0)
    val fillLine = Reg(UInt(c.lineAddrBits bits)) init (0)
    val fillWay = Reg(UInt(c.wayBits max 1 bits)) init (0)
    val fillErr = RegInit(False)

    val freeOh = OHMasking.first(~mshrValid)
    val freeIdx = OHToUInt(freeOh).resize(c.mshrBits)

    // Every port of the lookup's mask: pending again, waiting for MSHR k
    def replay(k: UInt): Unit =
      for (p <- 0 until N) when(mask(p)) {
        port(p).pend := True
        port(p).hold := True
        port(p).holdIdx := k
      }
    def countPorts(what: String): Unit =
      for (p <- 0 until N) count(s"port${p}_$what", mask(p))

    hitJobs.io.push.valid := False
    hitJobs.io.push.word := dataAddr(OHToUInt(hitOh), set, (blk @@ U(0, 2 bits)).resize(c.beatBits))
    hitJobs.io.push.mask := mask
    hitJobs.io.push.resp := B"00"
    ddrAr.valid := False
    ddrAr.line := line
    ddrAr.id := freeIdx
    fillDone.io.pop.ready := False

    // One write port each: the states below pick what it writes
    val tagWe = Bits(c.ways bits)
    val tagWa = UInt(c.setBits bits)
    val tagWd = Bits(c.tagBits + 1 bits)
    tagWe := 0
    tagWa := set
    tagWd := False ## tag.asBits
    for (w <- 0 until c.ways) tagMem(w).write(tagWa, tagWd, enable = tagWe(w))
    val lruWe = False
    val lruWa = UInt(c.setBits bits)
    val lruWd = Bits(c.lruBits bits)
    lruWa := set
    lruWd := lruTouch(lruNow, victim)
    lruMem.write(lruWa, lruWd, enable = lruWe)

    switch(state) {
      is(IDLE) {
        when(fillDone.io.pop.valid) {
          val k = fillDone.io.pop.payload
          fillK := k
          fillLine := Vec(mshr.map(_.line))(k)
          fillWay := Vec(mshr.map(_.way))(k)
          fillErr := Vec(mshr.map(_.err))(k)
          fillDone.io.pop.ready := True
          state := FILL
        } elsewhen (flushing) {
          when(!mshrValid.orR) {
            sweepSet := 0
            state := SWEEP
          }
        } elsewhen (eligible.orR) {
          lastGrant := grantOh
          gIdx := OHToUInt(grantOh).resized
          state := READ
        }
      }
      is(READ) {
        // Every eligible port asking for the granted block joins it
        val g = Vec(port.map(_.block))(gIdx)
        val m = Bits(N bits)
        for (p <- 0 until N) m(p) := port(p).eligible && port(p).block === g
        block := g
        mask := m
        for (p <- 0 until N) when(m(p)) { port(p).pend := False }
        state := WAIT
      }
      is(WAIT) {
        for (k <- 0 until c.mshrs) inFlight(k) := mshr(k).valid && mshr(k).line === line
        for (w <- 0 until c.ways) {
          val f = mshr.map(m => m.valid && setOf(m.line) === set && m.way === w)
          wayFilling(w) := f.reduce(_ || _)
          fillingIdx(w) := OHToUInt(OHMasking.first(Vec(f).asBits)).resize(c.mshrBits)
        }
        state := DECIDE
      }
      is(DECIDE) {
        val hits = Vec(tagQ.map(t => t.msb && t(c.tagBits - 1 downto 0).asUInt === tag)).asBits
        hitOh := hits
        val v = lruVictim(lruQ, wayFilling)
        victim := OHToUInt(v).resize(c.wayBits max 1)
        victimValid := (v & Vec(tagQ.map(_.msb)).asBits).orR
        lruNow := lruQ
        val flight = inFlight.orR
        val hit = hits.orR
        val setFull = wayFilling.andR
        val mshrFull = mshrValid.andR
        actJoin := flight
        actHit := !flight && hit
        actSetFull := !flight && !hit && setFull
        actMshrFull := !flight && !hit && !setFull && mshrFull
        actAlloc := !flight && !hit && !setFull && !mshrFull
        state := ACT
      }
      is(ACT) {
        // One of these, as DECIDE found
        when(actJoin) {
          val k = OHToUInt(inFlight).resize(c.mshrBits)
          val firstBeatNow = fill.in.valid && fill.k === k
          val canJoin = Vec(mshr.map(_.beats === 0))(k) && !firstBeatNow
          when(canJoin) {
            for (k2 <- 0 until c.mshrs) when(k === k2) { mshr(k2).mask := mshr(k2).mask | mask }
            count("merges", True)
            countPorts("merges")
          } otherwise {
            replay(k)
            count("replays", True)
            countPorts("replays")
          }
          count("lookups", True)
          state := IDLE
        }
        when(actHit) {
          hitJobs.io.push.valid := True
          when(hitJobs.io.push.ready) {
            lruWe := True
            lruWd := lruTouch(lruNow, OHToUInt(hitOh).resize(c.wayBits max 1))
            count("hits", True)
            countPorts("hits")
            count("multicast", CountOne(mask) - 1)
            count("lookups", True)
            state := IDLE
          }
        }
        when(actSetFull) {
          replay(MuxOH(lruVictim(lruNow, B(0, c.ways bits)), fillingIdx))
          count("replays", True)
          count("set_full", True)
          countPorts("replays")
          count("lookups", True)
          state := IDLE
        }
        when(actMshrFull) {
          replay(U(0, c.mshrBits bits)) // the first to finish frees one
          count("replays", True)
          count("mshr_full", True)
          countPorts("replays")
          count("lookups", True)
          state := IDLE
        }
        when(actAlloc && !readerBusy) {
          // The victim way: {tag, not valid} until its fill is done; the AR to DDR
          for (w <- 0 until c.ways) tagWe(w) := victim === w
          lruWe := True
          for (k2 <- 0 until c.mshrs) when(freeIdx === k2) {
            mshr(k2).valid := True
            mshr(k2).line := line
            mshr(k2).way := victim
            mshr(k2).mask := mask
            mshr(k2).beats := 0
            mshr(k2).err := False
          }
          ddrAr.valid := True
          count("misses", True)
          countPorts("misses")
          count("evictions", victimValid)
          count("ddr_reads", True)
          count("multicast", CountOne(mask) - 1)
          count("lookups", True)
          state := IDLE
        }
      }
      is(FILL) {
        // The line's last beat is in: valid in the tags (unless it came with an error), the MSHR
        // free, its waiters retry
        for (w <- 0 until c.ways) tagWe(w) := fillWay === w
        tagWa := setOf(fillLine)
        tagWd := !fillErr ## tagOf(fillLine).asBits
        for (k2 <- 0 until c.mshrs) when(fillK === k2) { mshr(k2).valid := False }
        for (p <- 0 until N) when(port(p).hold && port(p).holdIdx === fillK) { port(p).hold := False }
        state := IDLE
      }
      is(SWEEP) {
        tagWe.setAll()
        tagWa := sweepSet
        tagWd := 0
        lruWe := True
        lruWa := sweepSet
        lruWd := 0
        sweepSet := sweepSet + 1
        when(sweepSet === c.sets - 1) {
          flushing := False
          state := IDLE
        }
      }
    }
  }

  // ===========================================================================
  // Performance counters: 8 bits each in fabric, the upper 32 in a RAM (a carry a clock, its + 1
  // in a DSP)
  // ===========================================================================
  val perf = new Area {
    val enable = !CNT_FREEZE
    count("cycles", True)
    val idxBits = log2Up(K)
    val low = Vec.fill(K)(Reg(UInt(8 bits)) init (0))
    val carry = Vec.fill(K)(RegInit(False))
    val upper = Mem(UInt(32 bits), K) // CYCLES' 32, the others' 24 (and 8 unseen)
    upper.addAttribute("ram_style", "distributed")

    val clearing = RegInit(True)
    val clearIdx = Reg(UInt(idxBits bits)) init (0)
    when(clearPulse) {
      clearing := True
      clearIdx := 0
    }
    CNT_CLEAR := clearing

    // Low Performance counter - pack MSB's to RAM. A counter carries again 85 clocks later at the soonest: no hazard
    val pending = carry.asBits
    val pickOh = OHMasking.first(pending)
    val pick = !clearing && pending.orR
    val p1Valid = RegNext(pick) init (False)
    val p1Idx = RegNext(OHToUInt(pickOh).resize(idxBits))
    val p2Valid = RegNext(p1Valid && !clearing) init (False)
    val p2Idx = RegNext(p1Idx)
    val p2Upper = RegNext(upper.readAsync(p1Idx))
    val p2Sum = p2Upper + 1
    val p3Valid = RegNext(p2Valid && !clearing) init (False)
    val p3Idx = RegNext(p2Idx)
    val p3Upper = Reg(UInt(32 bits)) init (0)
    p3Upper := p2Sum
    when(clearPulse || clearing) { p3Upper := 0 }
    p2Sum.addAttribute("use_dsp", "yes")
    p3Upper.addAttribute("use_dsp", "yes")
    upper.write(
      address = Mux(clearing, clearIdx, p3Idx),
      data = p3Upper,
      enable = clearing || p3Valid
    )
    for (i <- 0 until K) {
      val sum = low(i).resize(9) + inc(i).resize(9)
      val picked = pick && pickOh(i)
      when(clearing) {
        low(i) := 0
        carry(i) := False
      } otherwise {
        when(enable) { low(i) := sum(7 downto 0) }
        carry(i) := (carry(i) && !picked) || (enable && sum(8))
      }
    }
    when(clearing) {
      clearIdx := clearIdx + 1
      when(clearIdx === K - 1) { clearing := False }
    }

    // A counter register read: the counter's RAM word and low byte, at the bus address (CYCLES'
    // two words, then a word each)
    val rdAddress = busif.readAddress()
    val rdIdx = Mux(
      rdAddress < L2Cache.counterAddress(1),
      U(0, idxBits bits),
      ((rdAddress - (L2Cache.counterBase + 4)) >> 2).resize(idxBits)
    )
    val rdUpper = upper.readAsync(rdIdx)
    cntLo := rdUpper(23 downto 0) @@ low(rdIdx)
    cntHi := rdUpper(31 downto 24)
    CNT_PENDING := carry.asBits.orR || p1Valid || p2Valid || p3Valid
  }
}

// Another configuration from key=value arguments: kib=, ways=, clock=core|mem, latency=
// (dataReadLatency), line= (lineBytes), dir= (the target directory)
object L2CacheVerilog {
  def main(args: Array[String]): Unit = {
    val a = args.map(_.split("=", 2)).collect { case Array(k, v) => k -> v }.toMap
    val d = L2CacheConfig()
    val config = d.copy(
      totalBytes = a.get("kib").fold(d.totalBytes)(_.toInt * 1024),
      ways = a.get("ways").fold(d.ways)(_.toInt),
      onMemClock = a.get("clock").fold(d.onMemClock)(_ == "mem"),
      dataReadLatency = a.get("latency").fold(d.dataReadLatency)(_.toInt),
      lineBytes = a.get("line").fold(d.lineBytes)(_.toInt)
    )
    SpinalConfig(
      targetDirectory = a.getOrElse("dir", "rtl/L2Cache"),
      defaultConfigForClockDomains = ClockDomainConfig(resetActiveLevel = LOW, resetKind = SYNC)
    ).withPrivateNamespace.generateVerilog(new L2Cache(config))
  }
}
