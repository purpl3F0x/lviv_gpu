package lviv_gpu_modules

import spinal.core._
import spinal.core.sim._
import spinal.lib._
import spinal.lib.bus.amba4.axi._
import scala.collection.mutable
import scala.util.Random

// =============================================================================
// An AXI4 read slave: bursts in flight up to a limit, answered in order after a latency, the data
// a hash of the beat's address, RRESP by address range
// =============================================================================
class AxiReadOnlySlaveSim(axi: Axi4ReadOnly, cd: ClockDomain, rng: Random, c: AxiDataMoverConfig) {
  var limit = 8 // bursts accepted and not yet finished
  var latMin = 2 // clocks from the address to the first beat
  var latMax = 2
  var gapPercent = 0 // of the clocks: no beat offered
  var arGapPercent = 0 // of the clocks: AR not ready
  val badRanges = mutable.ArrayBuffer[(Long, Long, Int)]() // [from, to) bytes, RRESP
  var bursts = 0L
  var beats = 0L
  var inFlight = 0 // bursts
  var beatsInFlight = 0L // requested, not yet delivered
  var maxInFlight = 0

  case class Burst(addr: Long, len: Int, readyAt: Long)
  val queue = mutable.Queue[Burst]()

  def respFor(addr: Long): Int =
    badRanges.collectFirst { case (from, to, resp) if addr >= from && addr < to => resp }.getOrElse(0)

  def start(): Unit = {
    fork {
      axi.ar.ready #= false
      var cycle = 0L
      while (true) {
        cd.waitSampling()
        cycle += 1
        if (axi.ar.valid.toBoolean && axi.ar.ready.toBoolean) {
          val addr = axi.ar.addr.toLong
          val len = axi.ar.len.toInt
          assert(axi.ar.size.toInt == c.beatShift, s"AR size ${axi.ar.size.toInt}")
          assert(axi.ar.burst.toInt == 1, "AR not INCR")
          assert(addr % c.beatBytes == 0, f"AR 0x$addr%08x not beat aligned")
          assert(len < c.maxBurstBeats, s"AR of ${len + 1} beats")
          assert((addr & 0xfff) + c.beatBytes * (len + 1) <= 4096, f"AR 0x$addr%08x of ${len + 1} beats crosses 4 KiB")
          assert(axi.ar.cache.toInt == 3 && axi.ar.prot.toInt == 0 && axi.ar.user.toInt == 0, "AR cache/prot/user")
          queue.enqueue(Burst(addr, len, cycle + latMin + rng.nextInt(latMax - latMin + 1)))
          bursts += 1
          inFlight += 1
          beatsInFlight += len + 1
          maxInFlight = maxInFlight max inFlight
        }
        axi.ar.ready #= inFlight < limit && rng.nextInt(100) >= arGapPercent
      }
    }

    fork {
      var current: Burst = null
      var beat = 0
      var cycle = 0L
      axi.r.valid #= false
      while (true) {
        cd.waitSampling()
        cycle += 1
        assert(axi.r.ready.toBoolean, "RREADY low")
        val valid = axi.r.valid.toBoolean
        if (valid) {
          beats += 1
          beatsInFlight -= 1
          if (beat == current.len) {
            current = null
            inFlight -= 1
          } else beat += 1
        }
        if (current == null && queue.nonEmpty && queue.head.readyAt <= cycle) {
          current = queue.dequeue()
          beat = 0
        }
        if (current != null && rng.nextInt(100) >= gapPercent) {
          val addr = current.addr + beat.toLong * c.beatBytes
          axi.r.valid #= true
          axi.r.data #= AxiDataMoverSim.beatData(addr, c)
          axi.r.resp #= respFor(addr)
          axi.r.last #= beat == current.len
        } else axi.r.valid #= false
      }
    }
  }
}

// =============================================================================
// The DataMover on Verilator: random commands against a reference of every beat and status
// =============================================================================
object AxiDataMoverSim extends App {
  val rng = new Random(0xda7a)

  case class Cmd(saddr: Long, btt: Long, eof: Boolean, tag: Int, incr: Boolean = true) {
    def word: BigInt =
      BigInt(btt) | (BigInt(if (incr) 1 else 0) << 23) | (BigInt(if (eof) 1 else 0) << 30) | (BigInt(saddr) << 32) |
        (BigInt(tag) << 64)
  }

  // A beat's data: each 64-bit lane a mix of its address
  def beatData(beatAddr: Long, c: AxiDataMoverConfig): BigInt = {
    var v = BigInt(0)
    for (lane <- 0 until c.dataWidth / 64) {
      var x = (beatAddr + 8L * lane) * 0x9e3779b97f4a7c15L
      x ^= x >>> 29
      x *= 0xbf58476d1ce4e5b9L
      x ^= x >>> 32
      v |= (BigInt(x) & ((BigInt(1) << 64) - 1)) << (64 * lane)
    }
    v
  }

  val mask64 = (BigInt(1) << 64) - 1

  def run(c: AxiDataMoverConfig, name: String)(body: (AxiDataMover, AxiReadOnlySlaveSim) => Unit): Unit = {
    // Icarus, as AxiVisibilityDmaSim; SPINAL_SIM_VERILATOR=1 for Verilator (SpinalHDL 1.12.3's
    // wrapper does not build on Verilator 5.05: VlWide is no longer a WData pointer)
    val base = SimConfig
      .withConfig(SpinalConfig(defaultConfigForClockDomains = ClockDomainConfig(resetKind = SYNC, resetActiveLevel = LOW)))
      .workspacePath(sys.env.getOrElse("SPINAL_SIM_WORKSPACE", "simWorkspace"))
    val sim = if (sys.env.contains("SPINAL_SIM_VERILATOR")) base.withVerilator.allOptimisation else base.withIVerilog
    sim
      .compile {
        val dut = new AxiDataMover(c)
        dut.sp.free.simPublic()
        dut.occ.simPublic()
        dut
      }
      .doSim(name) { dut =>
        dut.clockDomain.forkStimulus(period = 10)
        dut.io.s_cmd.valid #= false
        dut.io.m_axis.ready #= false
        dut.io.m_sts.ready #= false
        val mem = new AxiReadOnlySlaveSim(dut.io.m_axi, dut.clockDomain, rng, c)
        mem.start()
        // Reserved and resident beats never exceed the FIFO
        fork {
          while (true) {
            dut.clockDomain.waitSampling()
            val free = dut.sp.free.toLong
            val occ = dut.occ.toLong
            assert(free <= c.fifoBeats, s"free $free")
            assert(occ + mem.beatsInFlight <= c.fifoBeats, s"FIFO over: $occ resident, ${mem.beatsInFlight} in flight")
          }
        }
        dut.clockDomain.waitSampling(5)
        body(dut, mem)
      }
  }

  // The commands' expected beats (data, keep, last) and status bytes, as the model of the IP
  class Reference(c: AxiDataMoverConfig, mem: AxiReadOnlySlaveSim) {
    val beats = mutable.Queue[(BigInt, BigInt, Boolean, Int)]() // data, keep, tlast, tag
    val statuses = mutable.Queue[Int]()
    var errorSeen = false

    def add(cmd: Cmd): Unit = {
      if (cmd.btt == 0 || !cmd.incr) {
        statuses.enqueue(0x10 | cmd.tag)
        errorSeen = true
        return
      }
      var slv = false
      var dec = false
      var addr = cmd.saddr
      var left = cmd.btt
      while (left > 0) {
        val lead = (addr % c.beatBytes).toInt
        val bytes = scala.math.min(c.beatBytes - lead, left).toInt
        val beatAddr = addr - lead
        val keep = ((BigInt(1) << bytes) - 1) << lead
        val last = left == bytes
        beats.enqueue((beatData(beatAddr, c), keep, cmd.eof && last, cmd.tag))
        mem.respFor(beatAddr) match {
          case 2 => slv = true
          case 3 => dec = true
          case _ =>
        }
        addr += bytes
        left -= bytes
      }
      val okay = !slv && !dec
      statuses.enqueue((if (okay) 0x80 else 0) | (if (slv) 0x40 else 0) | (if (dec) 0x20 else 0) | cmd.tag)
      if (!okay) errorSeen = true
    }
  }

  // Drives the commands, randomises the two ready inputs, checks every beat and status; returns
  // the clocks from the first command to the last status
  def play(dut: AxiDataMover, mem: AxiReadOnlySlaveSim, cmds: Seq[Cmd], axisFactor: Double, stsFactor: Double,
           cmdGapPercent: Int, stsStalls: Boolean = false): Long = {
    val c = dut.config
    val ref = new Reference(c, mem)
    cmds.foreach(ref.add)
    val expectedBeats = ref.beats.size
    val expectedSts = ref.statuses.size
    var beatsSeen = 0L
    var stsSeen = 0L
    var start = -1L
    var end = -1L
    var cycle = 0L
    val clock = fork {
      while (true) {
        dut.clockDomain.waitSampling()
        cycle += 1
      }
    }

    val readyA = fork {
      while (true) {
        dut.clockDomain.waitSampling()
        dut.io.m_axis.ready #= rng.nextDouble() < axisFactor
      }
    }
    val readyS = fork {
      var stall = 0
      while (true) {
        dut.clockDomain.waitSampling()
        if (stall > 0) {
          stall -= 1
          dut.io.m_sts.ready #= false
        } else {
          if (stsStalls && rng.nextInt(50) == 0) stall = 20 + rng.nextInt(60)
          dut.io.m_sts.ready #= rng.nextDouble() < stsFactor
        }
      }
    }
    val monA = fork {
      while (true) {
        dut.clockDomain.waitSampling()
        if (dut.io.m_axis.valid.toBoolean && dut.io.m_axis.ready.toBoolean) {
          assert(ref.beats.nonEmpty, "a beat past the last expected")
          val (data, keep, last, tag) = ref.beats.dequeue()
          val gotKeep = dut.io.m_axis.keep.toBigInt
          val gotLast = dut.io.m_axis.last.toBoolean
          assert(gotKeep == keep, f"beat $beatsSeen (tag $tag): keep 0x$gotKeep%016x, expected 0x$keep%016x")
          assert(gotLast == last, s"beat $beatsSeen (tag $tag): last $gotLast, expected $last")
          // Only the kept bytes must match
          val got = dut.io.m_axis.data.toBigInt
          for (i <- 0 until c.beatBytes if keep.testBit(i))
            assert(((got >> (8 * i)) & 0xff) == ((data >> (8 * i)) & 0xff), f"beat $beatsSeen (tag $tag): byte $i")
          beatsSeen += 1
        }
      }
    }
    val monS = fork {
      while (true) {
        dut.clockDomain.waitSampling()
        if (dut.io.m_sts.valid.toBoolean && dut.io.m_sts.ready.toBoolean) {
          assert(ref.statuses.nonEmpty, "a status past the last expected")
          val expected = ref.statuses.dequeue()
          val got = dut.io.m_sts.payload.toInt
          assert(got == expected, f"status $stsSeen: 0x$got%02x, expected 0x$expected%02x")
          stsSeen += 1
          if (stsSeen == expectedSts) end = cycle
        }
      }
    }

    start = cycle
    for (cmd <- cmds) {
      while (rng.nextInt(100) < cmdGapPercent) dut.clockDomain.waitSampling()
      dut.io.s_cmd.payload #= cmd.word
      dut.io.s_cmd.valid #= true
      dut.clockDomain.waitSamplingWhere(dut.io.s_cmd.ready.toBoolean)
      dut.io.s_cmd.valid #= false
    }
    val deadline = cycle + 200000 + 4 * expectedBeats
    while (stsSeen < expectedSts) {
      dut.clockDomain.waitSampling()
      assert(cycle < deadline, s"timeout: $stsSeen of $expectedSts statuses, $beatsSeen of $expectedBeats beats")
    }
    assert(beatsSeen == expectedBeats, s"$beatsSeen beats of $expectedBeats")
    assert(dut.io.mm2s_err.toBoolean == ref.errorSeen, "mm2s_err")
    dut.clockDomain.waitSampling(8)
    assert(dut.io.idle.toBoolean, "not idle at the end")
    assert(mem.beatsInFlight == 0 && mem.inFlight == 0)
    clock.terminate(); readyA.terminate(); readyS.terminate(); monA.terminate(); monS.terminate()
    end - start
  }

  val base = AxiDataMoverConfig()
  val small = AxiDataMoverConfig(cmdQueueDepth = 16, fifoBeats = 64)

  // Random commands: byte addresses, every BTT shape, a few zero and FIXED ones
  def randomCmds(n: Int, c: AxiDataMoverConfig, big: Boolean): Seq[Cmd] = Seq.fill(n) {
    val shape = rng.nextInt(if (big) 12 else 10)
    val btt: Long = shape match {
      case 0 => 0
      case 1 => 1 + rng.nextInt(64)
      case 2 => 63 + rng.nextInt(3)
      case 3 => 96 * (1 + rng.nextInt(20))
      case 4 => 4096 - 64 + rng.nextInt(128)
      case 5 => 1 + rng.nextInt(4096 * 2)
      case 6 => 96 * (1 + rng.nextInt(2))
      case 7 => 1 + rng.nextInt(16 * 64 * 3)
      case 8 => 1 + rng.nextInt(1 << 15)
      case 9 => 1 + rng.nextInt(1 << 12)
      case 10 => 1L << 19
      case _ => (1L << 23) - 1 - rng.nextInt(4096)
    }
    val saddr: Long = rng.nextInt(8) match {
      case 0 => rng.nextLong() & 0xffffffffL
      case 1 => (rng.nextLong() & 0xfffff000L) | (4096 - 1 - rng.nextInt(64))
      case 2 => (rng.nextLong() & 0xffffffc0L) | 32
      case 3 => rng.nextLong() & 0xffffffc0L
      case _ => rng.nextLong() & 0xffffffe0L
    }
    Cmd(saddr, btt, rng.nextBoolean(), rng.nextInt(16), incr = rng.nextInt(40) != 0)
  }

  def report(what: String, cycles: Long, beats: Long, cmds: Int): Unit =
    println(f"  $what: $cycles clocks, $beats beats (${beats.toDouble / cycles}%.3f a clock), $cmds commands (${cycles.toDouble / cmds}%.2f clocks each)")

  run(base, "AxiDataMover_directed") { (dut, mem) =>
    println("Test 1: directed commands")
    val cmds = Seq(
      Cmd(0x1000, 64, eof = false, tag = 1), // one aligned beat
      Cmd(0x2020, 96, eof = true, tag = 2), // the visibility DMA's odd triangle: two beats
      Cmd(0x3000, 96, eof = false, tag = 3), // an even one
      Cmd(0x4000, 0, eof = false, tag = 4), // INTERR
      Cmd(0x5fc0, 128, eof = true, tag = 5), // across a page
      Cmd(0x6001, 1, eof = false, tag = 6), // one byte
      Cmd(0x7fff, 2, eof = false, tag = 7), // two bytes across a page
      Cmd(0x8000, 96 * 4096, eof = false, tag = 8), // the visibility DMA's largest, 256 bursts
      Cmd(0x9000, 64, eof = false, tag = 9, incr = false), // FIXED: INTERR
      Cmd(0xa03f, (1L << 23) - 1, eof = true, tag = 10) // the largest BTT
    )
    val cycles = play(dut, mem, cmds, 1.0, 1.0, 0)
    report("directed", cycles, mem.beats, cmds.size)

    println("Test 2: errors")
    mem.badRanges += ((0x20000L, 0x20040L, 2))
    mem.badRanges += ((0x30000L, 0x31000L, 3))
    val errCmds = Seq(
      Cmd(0x1ffe0, 96, eof = false, tag = 1), // ends in the SLVERR beat
      Cmd(0x20040, 96, eof = false, tag = 2), // clean
      Cmd(0x30f80, 4096, eof = false, tag = 3), // starts in the DECERR page
      Cmd(0x20000, 64, eof = false, tag = 4) // SLVERR alone
    )
    play(dut, mem, errCmds, 1.0, 1.0, 0)
    mem.badRanges.clear()
    assert(dut.io.mm2s_err.toBoolean, "mm2s_err not sticky")
    println("  statuses and mm2s_err as expected")
  }

  run(base, "AxiDataMover_random") { (dut, mem) =>
    println("Test 3: random commands, random memory and ready")
    for (round <- 0 until 8) {
      mem.limit = Seq(1, 8, 64)(rng.nextInt(3))
      mem.latMin = Seq(2, 2, 20)(rng.nextInt(3))
      mem.latMax = mem.latMin + rng.nextInt(40)
      mem.gapPercent = Seq(0, 0, 30)(rng.nextInt(3))
      mem.arGapPercent = Seq(0, 50)(rng.nextInt(2))
      val axisFactor = Seq(1.0, 0.5, 0.05)(rng.nextInt(3))
      val stsFactor = Seq(1.0, 0.3)(rng.nextInt(2))
      if (rng.nextBoolean()) mem.badRanges += ((rng.nextLong() & 0xffff0000L, (rng.nextLong() & 0xffff0000L) + 0x10000, 2 + rng.nextInt(2)))
      val cmds = randomCmds(if (round == 7) 40 else 120, base, big = round == 7)
      val cycles = play(dut, mem, cmds, axisFactor, stsFactor, if (rng.nextBoolean()) 0 else 60, stsStalls = rng.nextBoolean())
      println(f"  round $round: limit ${mem.limit}, latency ${mem.latMin}..${mem.latMax}, gaps ${mem.gapPercent}%%, ready $axisFactor/$stsFactor: ${cmds.size} commands in $cycles clocks")
      mem.badRanges.clear()
    }
  }

  run(small, "AxiDataMover_small") { (dut, mem) =>
    println("Test 4: a 16-command queue and a 64-beat FIFO, every path full")
    for (round <- 0 until 4) {
      mem.limit = 64
      mem.latMin = 2
      mem.latMax = 30
      val axisFactor = Seq(1.0, 0.2)(rng.nextInt(2))
      val cmds = randomCmds(200, small, big = false)
      val cycles = play(dut, mem, cmds, axisFactor, 1.0, 0, stsStalls = true)
      println(s"  round $round: ${cmds.size} commands in $cycles clocks, at most ${mem.maxInFlight} bursts in flight")
    }
  }

  run(base, "AxiDataMover_throughput") { (dut, mem) =>
    println("Test 5: throughput")
    mem.limit = 64
    mem.latMin = 2
    mem.latMax = 2
    var cmds = (0 until 200).map(i => Cmd(0x100000L + i * 4096L, 4096, eof = false, tag = i & 15))
    var cycles = play(dut, mem, cmds, 1.0, 1.0, 0)
    report("64-beat commands, fast memory", cycles, mem.beats, cmds.size)
    assert(mem.beats.toDouble / cycles > 0.95, "under a beat a clock")

    mem.beats = 0
    cmds = (0 until 400).map(i => Cmd(0x200000L + i * 96L, 96, eof = false, tag = i & 15))
    cycles = play(dut, mem, cmds, 1.0, 1.0, 0)
    report("96-byte commands back to back", cycles, mem.beats, cmds.size)
    assert(cycles.toDouble / cmds.size < 2.3, "over 2 clocks a command")

    mem.beats = 0
    mem.limit = 64
    mem.latMin = 40
    mem.latMax = 40
    cmds = (0 until 400).map(i => Cmd(0x280000L + i * 96L, 96, eof = false, tag = i & 15))
    cycles = play(dut, mem, cmds, 1.0, 1.0, 0)
    report("96-byte commands, latency 40, the DMA's 32 bursts in flight", cycles, mem.beats, cmds.size)

    mem.beats = 0
    mem.limit = 8
    cmds = (0 until 400).map(i => Cmd(0x300000L + i * 96L, 96, eof = false, tag = i & 15))
    cycles = play(dut, mem, cmds, 1.0, 1.0, 0)
    report("96-byte commands, latency 40, 8 bursts in flight", cycles, mem.beats, cmds.size)

    mem.beats = 0
    mem.limit = 2
    cmds = (0 until 400).map(i => Cmd(0x400000L + i * 96L, 96, eof = false, tag = i & 15))
    cycles = play(dut, mem, cmds, 1.0, 1.0, 0)
    report("96-byte commands, latency 40, 2 bursts in flight", cycles, mem.beats, cmds.size)
  }

  val burst64 = AxiDataMoverConfig(maxBurstBeats = 64)
  run(burst64, "AxiDataMover_burst64") { (dut, mem) =>
    println("Test 6: 64-beat bursts, random commands")
    for (round <- 0 until 4) {
      mem.limit = Seq(1, 8)(rng.nextInt(2))
      mem.latMin = 2
      mem.latMax = 2 + rng.nextInt(30)
      mem.gapPercent = Seq(0, 30)(rng.nextInt(2))
      val cmds = randomCmds(100, burst64, big = round == 3)
      val cycles = play(dut, mem, cmds, Seq(1.0, 0.3)(rng.nextInt(2)), 1.0, 30)
      println(s"  round $round: ${cmds.size} commands in $cycles clocks, at most ${mem.maxInFlight} bursts in flight")
    }
  }

  println("ALL TESTS PASSED SUCCESSFULLY!")
}
