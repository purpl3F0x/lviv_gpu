package lviv_gpu_modules

import spinal.core._
import spinal.core.sim._
import spinal.lib._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.amba3.apb._
import scala.collection.mutable

// =============================================================================
// SpinalHDL Simulation Memory Model for Axi4WriteOnly Interface
// Models DRAM write slave behavior (AW, W, B channels) with Sparse Storage
// - stallPercent: probability (0..100) of deasserting AWREADY / WREADY on any cycle
// - Asserts that no burst crosses a 4KB boundary
// =============================================================================
class AxiWriteOnlyMemorySim(axi: Axi4WriteOnly, clockDomain: ClockDomain, stallPercent: Int = 0, seed: Long = 1) {
  val memory = mutable.Map[Long, Byte]()
  val rng = new scala.util.Random(seed)
  var burstCount = 0

  case class AwTransaction(addr: Long, len: Int, size: Int, id: Int)
  val awQueue = mutable.Queue[AwTransaction]()
  val bQueue = mutable.Queue[(Int, Int)]() // (id, resp)

  private def stall(): Boolean = stallPercent > 0 && rng.nextInt(100) < stallPercent

  def start(): Unit = {
    // AW Handshake Channel
    fork {
      axi.aw.ready #= !stall()
      while (true) {
        clockDomain.waitSampling()
        if (axi.aw.valid.toBoolean && axi.aw.ready.toBoolean) {
          val addr = axi.aw.payload.addr.toLong
          val len = axi.aw.payload.len.toInt
          val size = axi.aw.payload.size.toInt
          val id = axi.aw.payload.id.toInt
          val burstBytes = (len + 1) << size
          assert(
            (addr & 0xfff) + burstBytes <= 4096,
            f"AXI burst crosses 4KB boundary: addr=0x$addr%08X len=$len size=$size"
          )
          burstCount += 1
          awQueue.enqueue(AwTransaction(addr, len, size, id))
        }
        axi.aw.ready #= !stall()
      }
    }

    // W & B Handshake Channels
    fork {
      var currentAw: AwTransaction = null
      var beatIndex = 0
      axi.b.valid #= false
      axi.w.ready #= false

      while (true) {
        clockDomain.waitSampling()

        if (currentAw == null && awQueue.nonEmpty) {
          currentAw = awQueue.dequeue()
          beatIndex = 0
        }

        val wFire = axi.w.valid.toBoolean && axi.w.ready.toBoolean
        assert(!wFire || currentAw != null, "W beat accepted without a pending AW burst")

        if (wFire) {
          val wdata = axi.w.payload.data.toBigInt
          val wstrb = axi.w.payload.strb.toBigInt
          val wlast = axi.w.payload.last.toBoolean

          val bytesPerBeat = 1 << currentAw.size
          val beatAddr = currentAw.addr + (beatIndex * bytesPerBeat)

          for (byteIdx <- 0 until bytesPerBeat) {
            if (((wstrb >> byteIdx) & 1) != 0) {
              val byteVal = ((wdata >> (byteIdx * 8)) & 0xff).toByte
              memory(beatAddr + byteIdx) = byteVal
            }
          }

          if (wlast) {
            // Burst complete: schedule B OKAY response
            bQueue.enqueue((currentAw.id, 0)) // OKAY = 0
            if (awQueue.nonEmpty) {
              currentAw = awQueue.dequeue()
              beatIndex = 0
            } else {
              currentAw = null
              beatIndex = 0
            }
          } else {
            beatIndex += 1
          }
        }

        // Accept W only while an AW burst is pending (W-before-AW is not modeled)
        axi.w.ready #= (currentAw != null || awQueue.nonEmpty) && !stall()

        // Drive B Response Channel
        if (bQueue.nonEmpty) {
          val (bid, bresp) = bQueue.head
          axi.b.valid #= true
          axi.b.payload.id #= bid
          axi.b.payload.resp #= bresp
          if (axi.b.ready.toBoolean) {
            bQueue.dequeue()
          }
        } else {
          axi.b.valid #= false
        }
      }
    }
  }

  def readByte(addr: Long): Int = {
    memory.getOrElse(addr, 0.toByte).toInt & 0xff
  }

  def readInt(addr: Long): Long = {
    val b0 = readByte(addr + 0).toLong
    val b1 = readByte(addr + 1).toLong
    val b2 = readByte(addr + 2).toLong
    val b3 = readByte(addr + 3).toLong
    (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
  }
}

// =============================================================================
// SpinalHDL APB3 Simulation Driver for Control Slave Interface
// =============================================================================
class SimApbDriver(apb: Apb3, clockDomain: ClockDomain) {
  def reset(): Unit = {
    apb.PSEL #= 0
    apb.PENABLE #= false
    apb.PWRITE #= false
    apb.PADDR #= 0
    apb.PWDATA #= 0
  }

  // SETUP phase, then ACCESS phase until PREADY; returns PRDATA sampled on completion
  private def transfer(address: Long, write: Boolean, data: Long): Long = {
    apb.PSEL #= 1
    apb.PENABLE #= false
    apb.PWRITE #= write
    apb.PADDR #= address
    apb.PWDATA #= data
    clockDomain.waitSampling()

    apb.PENABLE #= true
    do {
      clockDomain.waitSampling()
    } while (!apb.PREADY.toBoolean)
    val rdata = apb.PRDATA.toLong

    apb.PSEL #= 0
    apb.PENABLE #= false
    clockDomain.waitSampling()
    rdata
  }

  def write(address: Long, data: Long): Unit = transfer(address, write = true, data)

  def read(address: Long): Long = transfer(address, write = false, 0)
}

// =============================================================================
// SpinalHDL Simulation Memory Model for BRAM Read Interface
// Simulates a dual-port BRAM:
// - Direct write interface for testbench image population
// - Synchronous read port connected to dut.io.tile_ram with configurable latency (1, 2... cycles)
// =============================================================================
class SimBramMemory(
    tileRam: TileRamReadPort,
    clockDomain: ClockDomain,
    beatShift: Int,
    totalBeats: Int,
    latency: Int = 1
) {
  require(latency >= 1, "BRAM read latency must be at least 1 cycle")
  val memory = mutable.Map[Int, BigInt]()

  def writeWord(wordAddr: Int, wordData: BigInt): Unit = {
    memory(wordAddr) = wordData
  }

  def start(): Unit = {
    tileRam.dout #= 0
    fork {
      val pipeline = Array.fill(latency)(BigInt(0))
      val validPipe = Array.fill(latency)(false)

      while (true) {
        clockDomain.waitSampling()

        // Shift pipeline stages forward
        for (i <- 0 until (latency - 1)) {
          pipeline(i) = pipeline(i + 1)
          validPipe(i) = validPipe(i + 1)
        }

        // Sample read request (respecting active-high tileRam.rst)
        if (tileRam.en.toBoolean && !tileRam.rst.toBoolean) {
          val byteAddr = tileRam.addr.toLong
          val wordAddr = (byteAddr >> beatShift).toInt
          val data = memory.getOrElse(wordAddr, BigInt(0))
          pipeline(latency - 1) = data
          validPipe(latency - 1) = true
        } else {
          pipeline(latency - 1) = BigInt(0)
          validPipe(latency - 1) = false
        }

        if (validPipe(0)) {
          tileRam.dout #= pipeline(0)
        }
      }
    }
  }
}

// =============================================================================
// Main Simulation Testbench: 128-bit Bus, 4x3 Grid (12 Tiles of 128x128)
// =============================================================================
object AxiTileDmaSim extends App {
  // Test Configuration: 128x128 tile, 128-bit AXI bus (4 px/clock), 4x3 grid
  val config = AxiTileDmaConfig(
    addressWidth = 32,
    pixelsPerClock = 4, // 4 pixels/clock = 128-bit AXI data bus
    tileWidth = 128, // 128 pixels wide
    tileHeight = 128, // 128 lines high
    maxBurstLength = 256,
    maxOutstanding = 8,
    idWidth = 4,
    cdcDepth = 16,
    useAutoAdvance = true,
    bramReadLatency = 4 // 3-cycle BRAM read latency (testing 3-cycle UltraScale+ BRAM pipeline mode)
  )

  // Fast simulation with IVerilog backend
  val simConfig = SimConfig
    .withConfig(
      SpinalConfig(
        defaultConfigForClockDomains = ClockDomainConfig(resetActiveLevel = LOW)
      )
    )
    .withIVerilog

  val compiled = simConfig.compile(new AxiTileDma(config))

  // Scenario 1: 4KB-aligned frame, no backpressure (throughput baseline, no 4KB splits)
  runGridTest("Aligned_FullSpeed", dramBaseAddr = 0x00010000L, frameRowStrideBytes = 2048, stallPercent = 0)

  // Scenario 2: non-power-of-2 stride (5 x 512 B) so tile lines land at varying offsets in 4KB pages;
  // random AW/W backpressure exercises the decoupled AW/W channels
  runGridTest("Stride2560_Stalls", dramBaseAddr = 0x00010000L, frameRowStrideBytes = 2560, stallPercent = 30)

  def runGridTest(name: String, dramBaseAddr: Long, frameRowStrideBytes: Int, stallPercent: Int): Unit =
    compiled.doSim(name) { dut =>
      // -------------------------------------------------------------------------
      // Dual Asynchronous Clock Stimulus Generation
      // AXI Bus Clock: 100 MHz (period 10 ns)
      // Fast RAM Clock: 200 MHz (period 5 ns)
      // -------------------------------------------------------------------------
      dut.clockDomain.forkStimulus(period = 10) // clk & reset (AXI domain)
      dut.ramClock.forkStimulus(period = 5) // ram_clk & ram_reset (RAM domain)

      val axiClock = dut.clockDomain
      val ramClock = dut.ramClock

      // Instantiate simulation helpers
      val apbDriver = new SimApbDriver(dut.io.s_apb, axiClock)
      apbDriver.reset()

      val dramSim = new AxiWriteOnlyMemorySim(dut.io.m_axi, axiClock, stallPercent)
      dramSim.start()

      // One BRAM model per 2x2 quad thread (64-bit words @ 4 px/clock)
      val bramSims = dut.io.tile_ram.map { port =>
        val sim = new SimBramMemory(
          tileRam = port,
          clockDomain = ramClock,
          beatShift = config.threadBeatShift,
          totalBeats = config.threadTotalBeats,
          latency = config.bramReadLatency
        )
        sim.start()
        sim
      }

      axiClock.waitSampling(10)
      ramClock.waitSampling(10)

      // Fast BRAM Write Helper (Populates one thread's 64-bit words in its quad Tile BRAM)
      def writeBramWord(thread: Int, wordAddr: Int, wordData: BigInt): Unit = {
        bramSims(thread).writeWord(wordAddr, wordData)
      }

      // -------------------------------------------------------------------------
      // TEST PARAMETERS: 4x3 Grid of 128x128 Tiles
      // -------------------------------------------------------------------------
      val gridTilesX = 4
      val gridTilesY = 3
      val tileWidth = 128
      val tileHeight = 128
      val frameWidthPixels = gridTilesX * tileWidth // 512 pixels
      val frameHeightLines = gridTilesY * tileHeight // 384 lines

      // Fill the quad thread BRAMs with test pattern: (tileX, tileY, localY, localX)
      // Thread t owns pixel (t & 1, t >> 1) of every 2x2 quad
      def fillTileBram(tileX: Int, tileY: Int): Unit = {
        for (thread <- 0 until config.quadThreads) {
          val quadOffX = thread & 1
          val quadOffY = thread >> 1
          for (quadRow <- 0 until tileHeight / 2) {
            for (beatX <- 0 until config.beatsPerRow) {
              val wordAddr = quadRow * config.beatsPerRow + beatX
              var word: BigInt = 0

              for (px <- 0 until config.threadPixels) {
                val quadX = beatX * config.threadPixels + px
                val localX = quadX * 2 + quadOffX
                val localY = quadRow * 2 + quadOffY
                // 32-bit pixel encoding: [31..24]=tileX, [23..16]=tileY, [15..8]=localY, [7..0]=localX
                val pixelVal = ((tileX.toLong & 0xff) << 24) |
                  ((tileY.toLong & 0xff) << 16) |
                  ((localY.toLong & 0xff) << 8) |
                  (localX.toLong & 0xff)
                word |= (BigInt(pixelVal) & 0xffffffffL) << (px * 32)
              }
              writeBramWord(thread, wordAddr, word)
            }
          }
        }
      }

      // Poll Interrupt RAW register (0x40) until DONE (bit 0) is asserted; returns RAW value
      def waitTileDone(label: String): Long = {
        var status = 0L
        var pollCycles = 0
        do {
          axiClock.waitSampling(10)
          status = apbDriver.read(0x40) // INTR_INT_RAW (bit 0 = done, bit 1 = error, bit 2 = frame_done)
          pollCycles += 10
          if (pollCycles % 2000 == 0) {
            val perf = apbDriver.read(0x24)
            val pos = apbDriver.read(0x1c)
            println(
              s"    [Poll $pollCycles] RawIntr=0x${status.toHexString}, PerfCycles=$perf, Pos=0x${pos.toHexString}"
            )
          }
        } while ((status & 0x01) == 0 && pollCycles < 50000)

        assert((status & 0x01) != 0, s"Timeout waiting for $label to finish!")
        status
      }

      println(s"======================================================================")
      println(s"Starting 2D Tile Frame Buffer DMA Simulation (128-bit Bus) - Scenario: $name")
      println(s"  Grid Size        : ${gridTilesX}x${gridTilesY} tiles (Total 12 tiles)")
      println(s"  Tile Resolution  : ${tileWidth}x${tileHeight} pixels (32-bit RGBA)")
      println(s"  AXI Bus Width    : 128 bits (${config.pixelsPerClock} pixels/clock)")
      println(s"  Frame Resolution : ${frameWidthPixels}x${frameHeightLines} pixels")
      println(s"  Frame Row Stride : ${frameRowStrideBytes} bytes")
      println(s"  AW/W Stall Rate  : ${stallPercent}%")
      println(s"  DRAM Base Address: 0x${dramBaseAddr.toHexString}")
      println(s"======================================================================")

      // Program DMA Control Registers via AXI-Lite
      apbDriver.write(0x08, dramBaseAddr & 0xffffffffL) // BASE_ADDR_LOW
      apbDriver.write(0x0c, (dramBaseAddr >> 32) & 0xffffffffL) // BASE_ADDR_HIGH
      apbDriver.write(0x10, frameRowStrideBytes) // STRIDE
      apbDriver.write(0x14, gridTilesX) // TILES_X = 4
      apbDriver.write(0x18, gridTilesY) // TILES_Y = 3
      apbDriver.write(0x48, 0x00) // INTR_INT_MASK = 0 (unmask done, error, frame_done)

      println("[AXI-Lite] Initialized BaseAddr, Stride, TilesX, TilesY, and Interrupt Mask registers.")

      val totalTiles = gridTilesX * gridTilesY
      var tileCount = 0

      // Transfer all tiles in 2D Raster Order: (0,0) -> (1,0) -> (2,0) -> (3,0) -> (0,1) ...
      for (tileY <- 0 until gridTilesY) {
        for (tileX <- 0 until gridTilesX) {
          tileCount += 1
          println(s"\n--- [Tile $tileCount/$totalTiles] Processing Tile ($tileX, $tileY) ---")

          // 1. Fill the quad thread BRAMs with this tile's test pattern
          fillTileBram(tileX, tileY)

          // 2. Trigger DMA Start via AXI-Lite
          apbDriver.write(0x00, 0x01) // START (bit 0)

          // 3. Wait for DONE
          val status = waitTileDone(s"Tile ($tileX, $tileY)")
          val perfCycles = apbDriver.read(0x24)
          val curPos = apbDriver.read(0x1c)
          val nextX = curPos & 0xffff
          val nextY = (curPos >> 16) & 0xffff

          println(f"    Completed in $perfCycles cycles. RawIntr=0x$status%X. Next Tile Pos=($nextX, $nextY)")

          // Clear DONE raw interrupt flag (W1C at 0x40)
          apbDriver.write(0x40, 0x01)

          // Check FRAME_DONE on the very last tile (3, 2)
          if (tileX == gridTilesX - 1 && tileY == gridTilesY - 1) {
            assert(
              (status & 0x04) != 0,
              "FRAME_DONE bit (0x04 in INTR_INT_RAW) must be asserted on final tile completion!"
            )
            assert(nextX == 0 && nextY == 0, "Tile coordinates must wrap back to (0,0) after frame completion!")
            println("    >> FRAME_DONE successfully asserted and coordinates wrapped to (0,0)!")
            apbDriver.write(0x40, 0x04) // Clear FRAME_DONE raw interrupt flag
          }
        }
      }

      // -------------------------------------------------------------------------
      // VERIFICATION: Check Entire 512x384 Frame in Simulated DRAM
      // -------------------------------------------------------------------------
      println("\n======================================================================")
      println("Verifying DRAM pixel buffer integrity across the full 512x384 frame...")
      println("======================================================================")

      var errorCount = 0

      for (globalY <- 0 until frameHeightLines) {
        for (globalX <- 0 until frameWidthPixels) {
          val expectedTileX = globalX / tileWidth
          val expectedTileY = globalY / tileHeight
          val expectedLocalX = globalX % tileWidth
          val expectedLocalY = globalY % tileHeight

          val expectedPixel = ((expectedTileX.toLong & 0xff) << 24) |
            ((expectedTileY.toLong & 0xff) << 16) |
            ((expectedLocalY.toLong & 0xff) << 8) |
            (expectedLocalX.toLong & 0xff)

          val pixelByteAddr = dramBaseAddr + (globalY * frameRowStrideBytes) + (globalX * 4)

          // Read 32-bit pixel from simulated DRAM
          val actualPixel = dramSim.readInt(pixelByteAddr)

          if (actualPixel != expectedPixel) {
            if (errorCount < 10) {
              println(
                f"[ERROR] Mismatch at Global ($globalX%3d, $globalY%3d) [DRAM Addr: 0x$pixelByteAddr%08X]: " +
                  f"Expected 0x$expectedPixel%08X (Tile=($expectedTileX,$expectedTileY), Local=($expectedLocalX,$expectedLocalY)), " +
                  f"Actual = 0x$actualPixel%08X"
              )
            }
            errorCount += 1
          }
        }
      }

      if (errorCount == 0) {
        val totalPixels = frameWidthPixels * frameHeightLines
        println(s"\n[SUCCESS] ALL $totalPixels PIXELS VERIFIED PERFECTLY IN DRAM!")
        println(s"  - 4x3 Grid (12 tiles of 128x128, 128-bit AXI bus) successfully verified.")
        println(s"  - Multi-cycle 2D raster stride & auto-advance verified.")
        println(s"  - Asynchronous dual-clock CDC verified without data corruption.")
        println(
          s"  - ${dramSim.burstCount} AXI bursts, none crossing a 4KB boundary."
        )
        println("======================================================================\n")
      } else {
        println(s"\n[FAILURE] Total $errorCount pixel mismatches found in DRAM!")
        assert(false, s"Test failed with $errorCount errors.")
      }

      // -------------------------------------------------------------------------
      // DEFERRED SOFT RESET: a SOFT_RESET written mid-transfer must wait for the tile
      // to complete, then reset the position; the next tile must start clean.
      // -------------------------------------------------------------------------
      def countTileErrors(dramTileX: Int, dramTileY: Int, patTileX: Int, patTileY: Int): Int = {
        var errors = 0
        for (localY <- 0 until tileHeight; localX <- 0 until tileWidth) {
          val expected = ((patTileX.toLong & 0xff) << 24) | ((patTileY.toLong & 0xff) << 16) |
            ((localY.toLong & 0xff) << 8) | (localX.toLong & 0xff)
          val addr = dramBaseAddr + (dramTileY * tileHeight + localY) * frameRowStrideBytes.toLong +
            (dramTileX * tileWidth + localX) * 4
          if (dramSim.readInt(addr) != expected) errors += 1
        }
        errors
      }

      println("Testing deferred SOFT_RESET during an active transfer...")
      fillTileBram(0x5a, 0x5a)
      apbDriver.write(0x00, 0x01) // START at tile (0,0)
      axiClock.waitSampling(200)
      apbDriver.write(0x00, 0x04) // SOFT_RESET while BUSY
      val statusDuring = apbDriver.read(0x04)
      assert((statusDuring & 0x01) != 0, "DMA must still be BUSY right after SOFT_RESET request")
      assert((statusDuring & 0x08) != 0, "SOFT_RESET_PENDING must be set while the transfer is active")
      apbDriver.write(0x00, 0x01) // START while reset pending: must be ignored

      waitTileDone("Tile with pending SOFT_RESET")
      apbDriver.write(0x40, 0x01)
      axiClock.waitSampling(10)
      val statusAfter = apbDriver.read(0x04)
      assert((statusAfter & 0x09) == 0, f"BUSY/SOFT_RESET_PENDING must clear after reset, STATUS=0x$statusAfter%X")
      assert(apbDriver.read(0x1c) == 0, "Tile position must be reset to (0,0) by the deferred SOFT_RESET")
      assert(countTileErrors(0, 0, 0x5a, 0x5a) == 0, "Tile in flight during SOFT_RESET must complete intact")

      fillTileBram(0x6b, 0x6b)
      apbDriver.write(0x00, 0x01) // START after reset
      waitTileDone("Tile after SOFT_RESET")
      apbDriver.write(0x40, 0x01)
      assert(countTileErrors(0, 0, 0x6b, 0x6b) == 0, "Tile after SOFT_RESET must not contain stale data")
      println("  - Deferred SOFT_RESET verified (pending flag, START blocked, position reset, clean restart).")
    }
}
