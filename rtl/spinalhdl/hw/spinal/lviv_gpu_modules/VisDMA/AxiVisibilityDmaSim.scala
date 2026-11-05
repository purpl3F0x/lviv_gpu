package lviv_gpu_modules

import spinal.core._
import spinal.core.sim._
import spinal.lib._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.amba3.apb._
import scala.collection.mutable
import scala.util.Random

// =============================================================================
// SpinalHDL Simulation Memory Model for Axi4ReadOnly Interface
// An address never written reads as noise: a read in the wrong place shows up in the commands
// =============================================================================
class AxiReadOnlyMemorySim(axi: Axi4ReadOnly, clockDomain: ClockDomain, rng: Random, dataWidth: Int) {
  val memory = mutable.Map[Long, BigInt]()
  var gapPercent = 0 // of the clocks: no R beat, and AR not ready
  var bursts = 0

  case class ArTransaction(addr: Long, len: Int, size: Int, id: Int)
  val arQueue = mutable.Queue[ArTransaction]()

  def setBeat(addr: Long, data: BigInt): Unit = memory(addr) = data

  def start(): Unit = {
    // AR Channel: every burst is one chunk, or the start of the last one
    fork {
      axi.ar.ready #= false
      while (true) {
        clockDomain.waitSampling()
        if (axi.ar.valid.toBoolean && axi.ar.ready.toBoolean) {
          val addr = axi.ar.payload.addr.toLong
          val len = axi.ar.payload.len.toInt
          val size = axi.ar.payload.size.toInt
          val id = axi.ar.payload.id.toInt
          assert(addr % 4096 == 0, f"AR 0x$addr%08X is not on a chunk")
          assert((len + 1) << size <= 4096, f"AR 0x$addr%08X of ${len + 1} beats leaves its chunk")
          assert(1 << size == dataWidth / 8, s"AR of size $size")
          arQueue.enqueue(ArTransaction(addr, len, size, id))
          bursts += 1
        }
        axi.ar.ready #= rng.nextInt(100) >= gapPercent
      }
    }

    // R Channel
    fork {
      var currentAr: ArTransaction = null
      var beatIndex = 0
      axi.r.valid #= false

      while (true) {
        clockDomain.waitSampling()
        val valid = axi.r.valid.toBoolean
        val ready = axi.r.ready.toBoolean

        if (valid && ready) {
          if (beatIndex == currentAr.len) {
            currentAr = null
          } else {
            beatIndex += 1
          }
        }
        if (currentAr == null && arQueue.nonEmpty) {
          currentAr = arQueue.dequeue()
          beatIndex = 0
        }

        if (!(valid && !ready)) {
          if (currentAr != null && rng.nextInt(100) >= gapPercent) {
            val beatAddr = currentAr.addr + (beatIndex.toLong << currentAr.size)
            axi.r.valid #= true
            axi.r.payload.data #= memory.getOrElse(beatAddr, BigInt(dataWidth, rng))
            axi.r.payload.id #= currentAr.id
            axi.r.payload.resp #= 0 // OKAY
            axi.r.payload.last #= (beatIndex == currentAr.len)
          } else {
            axi.r.valid #= false
          }
        }
      }
    }
  }
}

// =============================================================================
// SpinalHDL Simulation Behavioral Model for AXI DataMover
// =============================================================================
class SimDataMoverResponder(
    cmdStream: Stream[Bits],
    stsStream: Stream[Bits],
    clockDomain: ClockDomain,
    rng: Random,
    addressWidth: Int = 32
) {
  case class ReceivedCmd(
      btt: Long,
      tag: Int,
      saddr: Long,
      raw: BigInt
  )

  val receivedCommands = mutable.ArrayBuffer[ReceivedCmd]()
  val stsQueue = mutable.Queue[(Int, Boolean)]()
  var gapPercent = 0 // of the clocks: no command taken, no status offered
  var stalled = false // no command taken at all

  def start(): Unit = {
    // Consume Commands, PG022's fields: BTT [22:0], Type [23], DSA [29:24], EOF [30], DRR [31],
    // SADDR past them, TAG [3:0] past that
    fork {
      cmdStream.ready #= false
      while (true) {
        clockDomain.waitSampling()
        if (cmdStream.valid.toBoolean && cmdStream.ready.toBoolean) {
          val raw = cmdStream.payload.toBigInt
          val btt = (raw & 0x7fffff).toLong
          val saddr = ((raw >> 32) & ((BigInt(1) << addressWidth) - 1)).toLong
          val tag = ((raw >> (32 + addressWidth)) & 0xf).toInt
          assert(raw.testBit(23), "Command with Type 0 (FIXED)")
          assert(((raw >> 24) & 0xff) == 0, "Command with DSA, EOF or DRR set")
          assert((raw >> (32 + addressWidth + 4)) == 0, "Command with reserved bits set")

          receivedCommands += ReceivedCmd(btt, tag, saddr, raw)
          stsQueue.enqueue((tag, false)) // Normal OKAY response
        }
        cmdStream.ready #= !stalled && rng.nextInt(100) >= gapPercent
      }
    }

    // Emit Status Responses
    fork {
      stsStream.valid #= false
      while (true) {
        clockDomain.waitSampling()
        val valid = stsStream.valid.toBoolean
        if (valid && stsStream.ready.toBoolean) {
          stsQueue.dequeue()
        }
        if (!(valid && !stsStream.ready.toBoolean)) {
          if (stsQueue.nonEmpty && rng.nextInt(100) >= gapPercent) {
            val (tag, isError) = stsQueue.head
            stsStream.valid #= true
            stsStream.payload #= (if (!isError) 0x80 | (tag & 0xf) else 0x40 | (tag & 0xf))
          } else {
            stsStream.valid #= false
          }
        }
      }
    }
  }
}

// =============================================================================
// Simulation Testbench for AxiVisibilityDma (using IVerilog)
// =============================================================================
object AxiVisibilityDmaSim extends App {
  val config = AxiVisibilityDmaConfig(
    addressWidth = 32,
    axiDataWidth = 128, // 128-bit AXI Read Master
    bttWidth = 19,
    defaultBttLimit = 4096,
    maxTiles = 64,
    triangleSizeBytes = 96, // 96 B triangles: odd triangles start 32 B into a 64 B beat
    maxOutstandingReads = 4,
    cmdFifoDepth = 16, // Small, to reach their full cases
    stsFifoDepth = 4,
    vbFifoDepth = 32,
    useAutoAdvance = true
  )

  val triBytes = config.triangleSizeBytes
  val rng = new Random(0x51a7)

  // CTRL: START, IRQ_ENABLE, AUTO_ADV_EN
  val StartCpu = 0x01L
  val StartAuto = 0x0dL

  val simConfig = SimConfig
    .withConfig(
      SpinalConfig(
        defaultConfigForClockDomains = ClockDomainConfig(resetActiveLevel = LOW)
      )
    )
    .withIVerilog

  simConfig.compile(new AxiVisibilityDma(config)).doSim("AxiVisibilityDma_Test") { dut =>
    dut.clockDomain.forkStimulus(period = 10)
    dut.io.tri_stream_valid #= false
    dut.io.core_stall #= false

    val apbDriver = new SimApbDriver(dut.io.s_apb, dut.clockDomain)
    val vbMemory = new AxiReadOnlyMemorySim(dut.io.m_axi_vb, dut.clockDomain, rng, config.axiDataWidth)
    val dmResponder = new SimDataMoverResponder(
      cmdStream = dut.io.m_axis_datamover_cmd,
      stsStream = dut.io.s_axis_datamover_sts,
      clockDomain = dut.clockDomain,
      rng = rng,
      addressWidth = config.addressWidth
    )

    apbDriver.reset()
    vbMemory.start()
    dmResponder.start()

    dut.clockDomain.waitSampling(5)

    val vbBaseAddr = 0x40000000L
    val triBaseAddr = 0x80000000L

    // Tile `tile`'s bits in their chunks: noise past N, in the last beat too
    def writeTile(base: Long, tile: Int, tiles: Int, n: Int, visible: Int => Boolean): Unit = {
      val beats = (n + 127) / 128
      for (k <- 0 until beats) {
        var data = BigInt(0)
        for (bit <- 0 until config.trianglesPerBeat) {
          val triangle = k * config.trianglesPerBeat + bit
          if (if (triangle < n) visible(triangle) else rng.nextBoolean()) data = data.setBit(bit)
        }
        val page = (k / config.chunkBeats) * tiles + tile
        vbMemory.setBeat(base + (page.toLong << 12) + (k % config.chunkBeats) * 16L, data)
      }
    }

    // The maximal runs of [0, N), each split greedily: (first triangle, triangles)
    def expectedCommands(n: Int, visible: Int => Boolean, limit: Int): Seq[(Int, Int)] = {
      val commands = mutable.ArrayBuffer[(Int, Int)]()
      var i = 0
      while (i < n) {
        if (visible(i)) {
          var end = i
          while (end < n && visible(end)) end += 1
          var from = i
          while (end - from > limit) {
            commands += ((from, limit))
            from += limit
          }
          commands += ((from, end - from))
          i = end
        } else {
          i += 1
        }
      }
      commands.toSeq
    }

    def waitDone(what: String): Unit = {
      var timeout = 400000
      while ((apbDriver.read(0x04) & 0x02) == 0 && timeout > 0) {
        dut.clockDomain.waitSampling(5)
        timeout -= 1
      }
      assert(timeout > 0, s"Timeout waiting for $what")
    }

    def clearDone(): Unit = {
      apbDriver.write(0x04, 0x1a) // DONE, IRQ_STATUS, FRAME_DONE
      apbDriver.write(0x70, 0x07) // INTR_INT_RAW W1C (done, error, frame_done) drives io.irq
      dut.clockDomain.waitSampling(2)
    }

    // What the DMA issued for a tile, against the reference; the tags count from 0
    def checkTile(what: String, expected: Seq[(Int, Int)], visibleCount: Long, triBase: Long): Unit = {
      val commands = dmResponder.receivedCommands
      assert(commands.size == expected.size, s"$what: ${commands.size} commands, expected ${expected.size}")
      for ((((start, count), cmd), idx) <- expected.zip(commands).zipWithIndex) {
        val expAddr = triBase + start.toLong * triBytes
        assert(cmd.saddr == expAddr, f"$what: cmd $idx SADDR 0x${cmd.saddr}%08X, expected 0x$expAddr%08X")
        assert(cmd.btt == count.toLong * triBytes, s"$what: cmd $idx BTT ${cmd.btt}, expected ${count * triBytes}")
        assert(cmd.tag == idx % 16, s"$what: cmd $idx tag ${cmd.tag}")
      }
      assert(apbDriver.read(0x24) == visibleCount, s"$what: STAT_VIS ${apbDriver.read(0x24)}, expected $visibleCount")
      assert(apbDriver.read(0x28) == expected.size, s"$what: STAT_CMD ${apbDriver.read(0x28)}")
      assert(apbDriver.read(0x2c) == expected.size, s"$what: STAT_STS ${apbDriver.read(0x2c)}")
      assert((apbDriver.read(0x04) & 0x60) == 0, s"$what: an error flag is set")
      dmResponder.receivedCommands.clear()
    }

    println("=================================================================")
    println("Test 1: Register Read / Write and Address Alignment Checking")
    println("=================================================================")

    // Triangle Geometry Base Address: low bits below triAlignBytes (32 B for 96 B triangles) are ignored
    val triAlignMask = config.triAlignBytes - 1
    apbDriver.write(0x10, 0x8000107fL)
    val readTriLow = apbDriver.read(0x10)
    println(f"Wrote TRI_BASE_LOW: 0x8000107F, Read Back: 0x$readTriLow%08X (Lower bits 0x$triAlignMask%X must be 0)")
    assert((readTriLow & triAlignMask) == 0, "Error: low alignment bits of TRI_BASE_LOW were not ignored!")
    assert(
      (readTriLow & ~triAlignMask & 0xffffffffL) == (0x8000107fL & ~triAlignMask & 0xffffffffL),
      "Error: aligned TRI_BASE_LOW bits lost!"
    )

    // Visibility Buffer Base Address: 4 KiB aligned
    apbDriver.write(0x08, 0x40002fffL)
    val readVbLow = apbDriver.read(0x08)
    println(f"Wrote VB_BASE_LOW: 0x40002FFF, Read Back: 0x$readVbLow%08X (Lower 12 bits must be 0)")
    assert(readVbLow == 0x40002000L, "Error: lower 12 bits of VB_BASE_LOW were not ignored!")

    assert(apbDriver.read(0x20) == config.defaultBttLimit, "Error: BTT_LIMIT's reset value!")
    assert(apbDriver.read(0x38) == config.maxTiles, "Error: TILE_COUNT's reset value!")

    // Check ready pin is high when idle
    assert(dut.io.ready.toBoolean, "Error: engine ready output must be true when idle!")

    println("=================================================================")
    println("Test 2: Visibility Filtering & Run Merging (Tile 0)")
    println("=================================================================")
    val N = 16
    val tiles = 8
    apbDriver.write(0x08, vbBaseAddr)
    apbDriver.write(0x10, triBaseAddr)
    apbDriver.write(0x18, N) // TRI_COUNT = 16
    apbDriver.write(0x1c, 0) // TILE_INDEX = 0
    apbDriver.write(0x38, tiles)

    // Tri 0..2, 4..5, 8..12 and 15 (odd start, 32 B into a 64 B beat)
    val visibleTile0 = Set(0, 1, 2, 4, 5, 8, 9, 10, 11, 12, 15)
    writeTile(vbBaseAddr, 0, tiles, N, visibleTile0)
    writeTile(vbBaseAddr, 1, tiles, N, Set(0, 1))

    println("Triggering START for Tile 0...")
    apbDriver.write(0x00, StartAuto)
    waitDone("tile 0")
    println("Tile 0 transfer completed!")

    // Verify interrupt and ready
    assert(dut.io.irq.toBoolean, "Error: IRQ output must be high upon completion!")
    assert(dut.io.ready.toBoolean, "Error: ready output must be high when idle!")

    val testTwo = Seq((0, 3), (4, 2), (8, 5), (15, 1))
    assert(expectedCommands(N, visibleTile0, 4096) == testTwo, "The reference disagrees with the test")
    checkTile("Tile 0", testTwo, 11, triBaseAddr)

    println("=================================================================")
    println("Test 3: Tile Auto-Advancement to Tile 1")
    println("=================================================================")
    val curTileIdx = apbDriver.read(0x1c)
    println(f"Current TILE_INDEX after auto-advance: $curTileIdx (Expected 1)")
    assert(curTileIdx == 1, f"Expected TILE_INDEX == 1, got $curTileIdx")

    clearDone()
    assert(!dut.io.irq.toBoolean, "Error: IRQ should be deasserted after W1C clear!")

    println("Triggering START for Tile 1...")
    apbDriver.write(0x00, StartAuto)
    waitDone("tile 1")
    checkTile("Tile 1", Seq((0, 2)), 2, triBaseAddr)
    assert(apbDriver.read(0x1c) == 2, "Expected TILE_INDEX == 2")

    println("=================================================================")
    println("Test 4: Partial Last Beat (N = 13), the Noise Past It Ignored")
    println("=================================================================")
    clearDone()
    val oddN = 13
    apbDriver.write(0x18, oddN) // TRI_COUNT = 13

    // The last run reaches N: it closes there, whatever follows in the bits
    writeTile(vbBaseAddr, 2, tiles, oddN, Set(0, 1, 3, 4, 5, 6, 12))
    apbDriver.write(0x00, StartAuto)
    waitDone("tile 2")
    checkTile("Tile 2", Seq((0, 2), (3, 4), (12, 1)), 7, triBaseAddr)
    assert(apbDriver.read(0x1c) == 3, "Expected TILE_INDEX == 3")

    println("=================================================================")
    println("Test 5: BTT_LIMIT = 2 triangles splits a 5-triangle run starting on an odd triangle")
    println("=================================================================")
    clearDone()
    val limitN = 8
    apbDriver.write(0x18, limitN)
    apbDriver.write(0x20, 2) // BTT_LIMIT is a triangle count
    writeTile(vbBaseAddr, 3, tiles, limitN, Set(1, 2, 3, 4, 5))
    apbDriver.write(0x00, StartAuto)
    waitDone("tile 3")
    checkTile("Tile 3", Seq((1, 2), (3, 2), (5, 1)), 5, triBaseAddr)

    println("=================================================================")
    println("Test 6: Randomized against a Software Reference")
    println("=================================================================")
    // Runs of random lengths, some past a beat or a chunk; density the share of visible ones
    def randomRuns(n: Int, density: Double, meanRun: Int): Array[Boolean] = {
      val bits = new Array[Boolean](n)
      var i = 0
      while (i < n) {
        val length = 1 + rng.nextInt(2 * meanRun)
        val gap = 1 + rng.nextInt((2 * meanRun * (1 - density) / density).toInt max 1)
        for (j <- i until ((i + length) min n)) bits(j) = true
        i += length + gap
      }
      bits
    }

    def pattern(n: Int): (String, Array[Boolean]) = rng.nextInt(7) match {
      case 0 => ("empty", new Array[Boolean](n))
      case 1 => ("full", Array.fill(n)(true))
      case 2 => ("0101", Array.tabulate(n)(_ % 2 == 1))
      case 3 => ("sparse", randomRuns(n, 0.02, 20))
      case 4 => ("short runs", randomRuns(n, 0.3, 3))
      case 5 => ("past a beat", randomRuns(n, 0.5, 300))
      case 6 => ("past a chunk", randomRuns(n, 0.8, 20000))
    }

    val sizes = Seq(1, 2, 7, 8, 9, 127, 128, 129, 255, 256, 257, 4096, 32767, 32768, 32769, 70000)
    val tileCounts = Seq(1, 7, 60, 64)
    val limits = Seq(0, 1, 3, 127, 128, 129, 300, config.defaultBttLimit, config.maxBttTriangles, 6000)
    var cases = 0
    var issued = 0L

    for (round <- 0 until 80) {
      val n = sizes(round % sizes.size)
      val count = tileCounts(rng.nextInt(tileCounts.size))
      // 4 KiB aligned, not 256 KiB: the tile's page is added, not concatenated
      val base = vbBaseAddr + (rng.nextInt(1 << 12).toLong << 12)
      val triBase = triBaseAddr + (rng.nextInt(1 << 16).toLong * config.triAlignBytes)
      val (name, bits) = pattern(n)
      val visible = bits.count(identity)
      // Limits a full row would take thousands of commands with are for the short rows
      val usable = limits.filter(l => n <= 4096 || l == 0 || l >= 128)
      val requested = if (round % 3 == 0) config.defaultBttLimit else usable(rng.nextInt(usable.size))
      val limit = if (requested == 0 || requested > config.maxBttTriangles) config.maxBttTriangles else requested
      val gaps = if (round % 4 == 3) 30 else 0
      vbMemory.gapPercent = gaps
      dmResponder.gapPercent = gaps

      apbDriver.write(0x08, base)
      apbDriver.write(0x10, triBase)
      apbDriver.write(0x18, n)
      apbDriver.write(0x20, requested)
      apbDriver.write(0x38, count)

      val auto = round % 5 == 0 && n <= 4096
      if (auto) {
        // A frame: every tile in turn, the same bits, ending in FRAME_DONE and TILE_INDEX back at 0
        apbDriver.write(0x1c, 0)
        for (tile <- 0 until count) writeTile(base, tile, count, n, bits)
        for (tile <- 0 until count) {
          apbDriver.write(0x00, StartAuto)
          waitDone(s"round $round tile $tile")
          checkTile(s"round $round ($name, N $n, limit $limit, tile $tile of $count)",
            expectedCommands(n, bits, limit), visible, triBase)
          issued += expectedCommands(n, bits, limit).size
          val status = apbDriver.read(0x04)
          assert(((status & 0x10) != 0) == (tile == count - 1), s"FRAME_DONE at tile $tile of $count")
          assert(apbDriver.read(0x1c) == (tile + 1) % count, "TILE_INDEX after the tile")
          clearDone()
        }
      } else {
        // CPU mode: a few tiles in any order, the others' bits noise
        for (tile <- rng.shuffle((0 until count).toList).take(3)) {
          writeTile(base, tile, count, n, bits)
          apbDriver.write(0x1c, tile)
          apbDriver.write(0x00, StartCpu)
          waitDone(s"round $round tile $tile")
          checkTile(s"round $round ($name, N $n, limit $limit, tile $tile of $count)",
            expectedCommands(n, bits, limit), visible, triBase)
          issued += expectedCommands(n, bits, limit).size
          assert(apbDriver.read(0x1c) == tile, "TILE_INDEX moved in CPU mode")
          clearDone()
        }
      }
      vbMemory.memory.clear()
      cases += 1
    }
    vbMemory.gapPercent = 0
    dmResponder.gapPercent = 0
    println(s"$cases cases, $issued commands")

    println("=================================================================")
    println("Test 7: Throughput")
    println("=================================================================")
    def perfOf(n: Int, visible: Int => Boolean): Long = {
      writeTile(vbBaseAddr, 0, 1, n, visible)
      apbDriver.write(0x08, vbBaseAddr)
      apbDriver.write(0x10, triBaseAddr)
      apbDriver.write(0x18, n)
      apbDriver.write(0x1c, 0)
      apbDriver.write(0x20, 0)
      apbDriver.write(0x38, 1)
      apbDriver.write(0x00, StartCpu)
      waitDone("the throughput tile")
      val perf = apbDriver.read(0x34)
      dmResponder.receivedCommands.clear()
      clearDone()
      perf
    }

    apbDriver.write(0x00, 0x10) // CNT_CLEAR
    dut.clockDomain.waitSampling(16)

    val beats = 1000
    val perfEmpty = perfOf(beats * 128, _ => false)
    val perfFull = perfOf(beats * 128, _ => true)
    val perfRuns = perfOf(beats * 128, i => i % 1280 < 16) // A run every 10 beats, in the sim's fast DataMover
    println(s"$beats beats: empty $perfEmpty clocks, full $perfFull, a run every 10 beats $perfRuns")
    assert(perfEmpty <= beats + 40, s"An empty tile took $perfEmpty clocks")
    assert(perfFull <= beats + 80, s"A full tile took $perfFull clocks") // 24 commands
    assert(perfRuns <= beats + 40 + (beats / 10) * 12, s"A tile of short runs took $perfRuns clocks")

    println("=================================================================")
    println("Test 8: Stall Counters")
    println("=================================================================")
    dut.clockDomain.waitSampling(32)
    val busy = apbDriver.read(0x40)
    val commands = apbDriver.read(0x58)
    val expectedRuns = expectedCommands(beats * 128, _ => true, config.maxBttTriangles).size + beats / 10
    println(s"CNT_BUSY $busy, CNT_CMDS $commands")
    assert(busy == perfEmpty + perfFull + perfRuns, s"CNT_BUSY $busy, the tiles' PERF ${perfEmpty + perfFull + perfRuns}")
    assert(commands == expectedRuns, s"CNT_CMDS $commands, expected $expectedRuns")
    assert(apbDriver.read(0x44) + apbDriver.read(0x48) + apbDriver.read(0x4c) <= busy, "Waits past the busy cycles")
    apbDriver.write(0x00, 0x10)
    dut.clockDomain.waitSampling(16)
    for (address <- 0x40 to 0x58 by 4) assert(apbDriver.read(address) == 0, f"Counter 0x$address%02X after CNT_CLEAR")

    println("=================================================================")
    println("Test 9: SOFT_RESET Mid-Tile")
    println("=================================================================")
    val resetN = 40000
    dmResponder.stalled = true // Commands pile up: the scan and the reads stop part way
    vbMemory.gapPercent = 20
    writeTile(vbBaseAddr, 0, 1, resetN, i => i % 4 == 0)
    apbDriver.write(0x18, resetN)
    apbDriver.write(0x00, StartCpu)
    dut.clockDomain.waitSampling(2000)
    assert((apbDriver.read(0x04) & 0x01) != 0, "Expected the DMA busy on a stalled tile")
    apbDriver.write(0x00, 0x02) // SOFT_RESET
    var settle = 20000
    while ((apbDriver.read(0x04) & 0x01) != 0 && settle > 0) {
      dut.clockDomain.waitSampling(5)
      settle -= 1
    }
    assert(settle > 0, "SOFT_RESET left the DMA busy")
    dmResponder.stalled = false
    vbMemory.gapPercent = 0
    dut.clockDomain.waitSampling(200)
    dmResponder.receivedCommands.clear()
    dmResponder.stsQueue.clear()

    // The next tile is whole, with nothing of the last in it
    clearDone()
    val afterN = 1000
    writeTile(vbBaseAddr, 0, 1, afterN, i => i % 100 < 10)
    apbDriver.write(0x18, afterN)
    apbDriver.write(0x00, StartCpu)
    waitDone("the tile after SOFT_RESET")
    checkTile("after SOFT_RESET", expectedCommands(afterN, i => i % 100 < 10, config.maxBttTriangles), 100, triBaseAddr)

    println("=================================================================")
    println("ALL TESTS PASSED SUCCESSFULLY!")
    println("=================================================================")
  }
}
