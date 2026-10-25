package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._
import spinal.lib.fsm._

// Command processor: renders a frame on one START, doing what the CPU's driver does per tile.
//
// The CPU sets the frame up and keeps the interrupts: the DMAs' frame registers (buffers, triangle
// count, TILE_COUNT, frame buffer, stride, tiles, both DMAs at tile 0), their INT_MASK and INT_RAW,
// the frame buffers' clear, the z-buffers' clear and the frontend's box for tile 0; then SIZE and
// START here. The command processor writes the units' registers as a second master on the crossbar
// (Axi4ToApbXbar's m_axi_1, one single-beat access at a time) and reads nothing over it: it watches
//   - the DMAs' INT_RAW bits (irq_done, irq_error, irq_frame_done), events on their rising edge;
//     it acknowledges each done (writes it 1 in INT_RAW), so the next tile gives a new edge; the
//     errors and frame_done are the CPU's
//   - idle flags: the triangle path's, the frontend's empty, the orchestrator's and the threads'
//     empty and each z-buffer's ready
// It runs on the crossbar's clock (lpd_clk). Everything it watches comes raw from another: the
// DMAs, the triangle path and the frontend run on mem_clk, the orchestrator and the threads on
// core_clk. Each signal is captured here in a flop of its own clock, crosses through two flops
// (BufferCC), and is combined after. Every one is a level that lasts many cycles of this clock.
//
// Per tile:
//   1. visibility DMA START, with AUTO_ADV_EN (it moves to the next tile itself, back to 0 after
//      TILE_COUNT); wait its done, acknowledge it
//   2. wait settleCycles, then until every unit has been empty idleCycles in a row
//   3. tile DMA START (it moves to the next tile itself), the four z-buffer clears, and the next
//      tile's frontend box (tile 0's after the last tile, ready for the next frame)
//   4. wait the tile DMA's done and the clears; acknowledge the done
// The last tile's done comes with the tile DMA's frame_done: DONE. An error edge from a DMA or an
// error response to one of its accesses stops the frame with ERROR, CAUSE and TILE. SOFT_RESET puts
// the command processor back to its reset state (after the response of an access in flight); the
// units are not reset.
//
// MODE 0 (reset): the CPU drives the tiles and the command processor ignores START.

case class CommandProcessorConfig(
    tileShift: Int = 7, // tiles of 128 x 128 pixels
    threads: Int = 4,
    maxTiles: Int = 64, // bits in a triangle's visibility word
    // After the visibility DMA's done: this many cycles, then every unit empty this many cycles in a
    // row.
    settleCycles: Int = 8,
    idleCycles: Int = 16
) {
  val tileIndexWidth: Int = log2Up(maxTiles)
}

object CommandProcessor {
  val byteCount = 128 // APB window

  // CAUSE codes
  val causeNone = 0
  val causeVisDma = 1 // the visibility DMA's error
  val causeTileDma = 2 // the tile DMA's error
  val causeBus =
    3 // an error response to one of the command processor's own accesses
  val causeSize = 4 // WIDTH or HEIGHT 0, or more than maxTiles tiles

  // The units' registers it writes, from their regif maps (sdk/include/generated/<Name>/*.h).
  val intRaw = 0x40 // both DMAs' RFMS4 block: INT_RAW, write 1 to clear
  val intDone = 0x1

  val visCtrl = 0x00
  val visCtrlStart =
    0xd // START, AUTO_ADV_EN, and IRQ_ENABLE at its reset value
  val tileCtrl = 0x00
  val tileCtrlStart = 0x1

  val frontendBbMinX = 0x04
  val frontendBbMinY = 0x08
  val frontendBbMaxX = 0x0c
  val frontendBbMaxY = 0x10

  val threadZbuf = 0x04
}

case class CommandProcessorWrite() extends Bundle {
  val addr = UInt(Axi4ToApbXbar.addressWidth bits)
  val data = Bits(32 bits)
}

class CommandProcessor(
    config: CommandProcessorConfig = CommandProcessorConfig()
) extends Component {
  import CommandProcessor._

  val axiConfig = Axi4SharedToApb3Bridge
    .getConfigs(Axi4ToApbXbar.addressWidth, 32, Axi4ToApbXbar.idWidth)
    ._1

  val io = new Bundle {
    val s_apb = slave(
      Apb3(Apb3Config(addressWidth = log2Up(byteCount), dataWidth = 32))
    )
    val m_axi = master(Axi4(axiConfig)) // to the crossbar's m_axi_1

    // Raw, each in its own clock. mem_clk: the DMAs' INT_RAW bits, the triangle path's and the
    // frontend's idle
    val mem_clk = in Bool ()
    val mem_resetn = in Bool ()
    val vis_irq_done = in Bool ()
    val vis_irq_error = in Bool ()
    val tile_irq_done = in Bool ()
    val tile_irq_error = in Bool ()
    val tile_irq_frame_done = in Bool ()
    val tri_path_idle = in Bool () // DataMover stream, the skid buffer into the core
    val frontend_empty = in Bool ()

    // core_clk: the orchestrator's and the threads' idle, the z-buffers' ready
    val core_clk = in Bool ()
    val core_resetn = in Bool ()
    val orchestrator_empty = in Bool ()
    val thread_empty = in Bits (config.threads bits)
    val zbuf_ready = in Bits (config.threads bits) // low while the z-buffer clears
  }

  noIoPrefix()

  // m_axi_awaddr, ...: the crossbar's names for its master ports
  io.m_axi.flatten.foreach { signal =>
    val port = signal
      .getName()
      .replace("m_axi_", "")
      .replace("_payload_", "")
      .replace("_", "")
    signal.setName(s"m_axi_$port")
  }

  // ---------------------------------------------------------------------------
  // Registers
  // ---------------------------------------------------------------------------

  val busif = Apb3BusInterface(io.s_apb, (0x0000, byteCount), "CP")

  val REG_CTRL = busif.newRegAt(address = 0x00, doc = "Control")
  val START = REG_CTRL.field(
    Bool(),
    W1P,
    doc = "Render a frame; ignored in MODE 0 and while BUSY"
  )
  val SOFT_RESET = REG_CTRL.field(
    Bool(),
    W1P,
    doc =
      "Back to the reset state (MODE kept), after the response of a register access in flight. " +
        "The units are not reset"
  )

  val REG_STATUS = busif.newRegAt(address = 0x04, doc = "Status")
  val BUSY = REG_STATUS.field(Bool(), RO, doc = "A frame is being rendered")
  val DONE = REG_STATUS.field(
    Bool(),
    W1C,
    doc = "The last frame finished (write 1 to clear)"
  )
  val ERROR = REG_STATUS.field(
    Bool(),
    W1C,
    doc = "The last frame stopped: CAUSE, TILE (write 1 to clear)"
  )
  val CAUSE = REG_STATUS.fieldAt(
    pos = 4,
    UInt(3 bits),
    RO,
    doc =
      "Why it stopped: 1 visibility DMA error, 2 tile DMA error, 3 error response to a register " +
        "access, 4 WIDTH or HEIGHT 0 or too many tiles"
  )
  val TILE = REG_STATUS.fieldAt(
    pos = 8,
    UInt(config.tileIndexWidth bits),
    RO,
    doc = "The tile being rendered, or the one the frame stopped at"
  )

  val REG_MODE = busif.newRegAt(address = 0x08, doc = "Mode")
  val MODE = REG_MODE.field(
    Bool(),
    RW,
    resetValue = 0,
    doc =
      "0: the CPU drives the tiles, START is ignored; 1: the command processor renders a frame on " +
        "START. Not changed while BUSY"
  )

  val REG_SIZE = busif.newRegAt(address = 0x0c, doc = "Frame size")
  val WIDTH =
    REG_SIZE.field(UInt(16 bits), RW, resetValue = 0, doc = "Pixels per row")
  val HEIGHT = REG_SIZE.field(UInt(16 bits), RW, resetValue = 0, doc = "Rows")

  val REG_FRAME_CYCLES = busif.newRegAt(address = 0x10, doc = "Frame cycles")
  val FRAME_CYCLES = REG_FRAME_CYCLES.field(
    UInt(32 bits),
    RO,
    doc = "Clock cycles the last frame took (so far)"
  )

  busif.accept(HtmlGenerator("command_processor_regmap", "CP"))
  busif.accept(CHeaderGenerator("command_processor_regmap", "CP"))
  busif.accept(JsonGenerator("command_processor_regmap"))

  // SOFT_RESET waits for the response of an access in flight, and no access starts meanwhile
  val softResetPending = RegInit(False)
  when(SOFT_RESET)(softResetPending := True)

  // ---------------------------------------------------------------------------
  // Register accesses on the crossbar, one at a time
  // ---------------------------------------------------------------------------

  val access = new Area {
    val busy = RegInit(False)
    val awPending, wPending = RegInit(False)
    val addr = Reg(UInt(Axi4ToApbXbar.addressWidth bits)) init (0)
    val data = Reg(Bits(32 bits)) init (0)
    val done = False // the response came, this cycle
    val error = False // ... and it was not OKAY

    def write(w: CommandProcessorWrite): Unit = when(!softResetPending) {
      busy := True
      awPending := True
      wPending := True
      addr := w.addr
      data := w.data
    }

    io.m_axi.aw.valid := awPending
    io.m_axi.aw.addr := addr
    io.m_axi.aw.id := 0
    io.m_axi.aw.len := 0
    io.m_axi.aw.size := 2
    io.m_axi.aw.burst := Axi4.burst.INCR
    io.m_axi.w.valid := wPending
    io.m_axi.w.data := data
    io.m_axi.w.strb := B"1111"
    io.m_axi.w.last := True
    io.m_axi.b.ready := True
    io.m_axi.ar.valid := False // reads nothing
    io.m_axi.ar.addr := addr
    io.m_axi.ar.id := 0
    io.m_axi.ar.len := 0
    io.m_axi.ar.size := 2
    io.m_axi.ar.burst := Axi4.burst.INCR
    io.m_axi.r.ready := True

    when(io.m_axi.aw.fire)(awPending := False)
    when(io.m_axi.w.fire)(wPending := False)
    when(io.m_axi.b.fire) {
      busy := False
      done := True
      error := io.m_axi.b.resp =/= Axi4.resp.OKAY
    }
    when(io.m_axi.r.fire) {
      busy := False
      done := True
      error := io.m_axi.r.resp =/= Axi4.resp.OKAY
    }
  }

  val softReset = softResetPending && !access.busy
  when(softReset) {
    softResetPending := False
  }

  // Inputs from the other clocks, from far across the design: each captured in a flop of its own
  // clock (free to sit near it), so that its crossing starts at a flop with no logic before it;
  // then two flops in this clock, and combined there. Bits synchronised apart can resolve a cycle
  // apart: the drain window covers that, and an event waits for its own bit.
  def otherClock(clock: Bool, resetn: Bool) =
    ClockDomain(
      clock,
      resetn,
      config = ClockDomainConfig(resetActiveLevel = LOW, resetKind = SYNC)
    )
  def allReady = B((1 << config.threads) - 1, config.threads bits)
  val memFlags = new ClockingArea(otherClock(io.mem_clk, io.mem_resetn)) {
    val visIrqDone = RegNext(io.vis_irq_done) init (False)
    val visIrqError = RegNext(io.vis_irq_error) init (False)
    val tileIrqDone = RegNext(io.tile_irq_done) init (False)
    val tileIrqError = RegNext(io.tile_irq_error) init (False)
    val tileIrqFrameDone = RegNext(io.tile_irq_frame_done) init (False)
    val triPathIdle = RegNext(io.tri_path_idle) init (False)
    val frontendEmpty = RegNext(io.frontend_empty) init (False)
  }
  val coreFlags = new ClockingArea(otherClock(io.core_clk, io.core_resetn)) {
    val orchestratorEmpty = RegNext(io.orchestrator_empty) init (False)
    val threadEmpty = RegNext(io.thread_empty) init (0)
    val zbufReady = RegNext(io.zbuf_ready) init (allReady)
  }
  val visIrqDone = BufferCC(memFlags.visIrqDone, init = False)
  val visIrqError = BufferCC(memFlags.visIrqError, init = False)
  val tileIrqDone = BufferCC(memFlags.tileIrqDone, init = False)
  val tileIrqError = BufferCC(memFlags.tileIrqError, init = False)
  val tileIrqFrameDone = BufferCC(memFlags.tileIrqFrameDone, init = False)
  val triPathIdle = BufferCC(memFlags.triPathIdle, init = False)
  val frontendIdle = BufferCC(memFlags.frontendEmpty, init = False)
  val orchestratorEmpty = BufferCC(coreFlags.orchestratorEmpty, init = False)
  val threadEmpty =
    BufferCC(coreFlags.threadEmpty, init = B(0, config.threads bits))
  val zbufReady = BufferCC(coreFlags.zbufReady, init = allReady)
  val threadIdle = orchestratorEmpty && threadEmpty.andR
  val zbufBusy = ~zbufReady

  // ---------------------------------------------------------------------------
  // The frame: everything here back to its reset value on SOFT_RESET
  // ---------------------------------------------------------------------------

  val frame = new ResetArea(softReset, cumulative = true) {
    def rise(signal: Bool): Bool = signal && !RegNext(signal, init = False)

    // Events, latched from their rising edge until armed again (cleared) by the sequencer
    val visDone, visError, tileDone, tileError, frameDone = RegInit(False)
    when(rise(visIrqDone))(visDone := True)
    when(rise(visIrqError))(visError := True)
    when(rise(tileIrqDone))(tileDone := True)
    when(rise(tileIrqError))(tileError := True)
    when(rise(tileIrqFrameDone))(frameDone := True)

    // A z-buffer clear is done once its busy has been seen rising, then falling
    val zbufRose = Reg(Bits(config.threads bits)) init (0)
    val zbufDone = Reg(Bits(config.threads bits)) init (0)
    for (n <- 0 until config.threads) {
      when(zbufBusy(n))(zbufRose(n) := True)
      when(zbufRose(n) && !zbufBusy(n))(zbufDone(n) := True)
    }

    // Every unit empty, for idleCycles in a row. Registered: the AND of the synchronised flags, not
    // the drain counter, sits after them
    val unitsIdle =
      RegNext(triPathIdle && frontendIdle && threadIdle) init (False)
    val waitCycles = Reg(
      UInt(log2Up(config.settleCycles.max(config.idleCycles) + 1) bits)
    ) init (0)

    val tileSize = 1 << config.tileShift
    val tilesXNext =
      ((WIDTH.resize(17 bits) + (tileSize - 1)) >> config.tileShift)
        .resize(10 bits)
    val tilesYNext =
      ((HEIGHT.resize(17 bits) + (tileSize - 1)) >> config.tileShift)
        .resize(10 bits)
    val badSize =
      tilesXNext === 0 || tilesYNext === 0 || (tilesXNext * tilesYNext) > config.maxTiles

    val busy = RegInit(False)
    val finished = False // the frame finished, this cycle
    val failed = False // the frame stopped, or did not start, this cycle
    val cause = Reg(UInt(3 bits)) init (causeNone)
    val tilesX, tilesY = Reg(UInt(config.tileIndexWidth + 1 bits)) init (1)
    val tileX, tileY = Reg(UInt(config.tileIndexWidth bits)) init (0)
    val tile = Reg(UInt(config.tileIndexWidth bits)) init (0)
    val lastX = tileX.resize(config.tileIndexWidth + 1 bits) === tilesX - 1
    val lastTile =
      lastX && tileY.resize(config.tileIndexWidth + 1 bits) === tilesY - 1
    val cycles = Reg(UInt(32 bits)) init (0)
    val item = Reg(UInt(4 bits)) init (0) // in the write list being sent
    when(busy)(cycles := cycles + 1)

    // The next tile: the one after, or tile 0 after the last, ready for the next frame
    val first = U(0, config.tileIndexWidth bits)
    val nextX = Mux(lastX, first, tileX + 1) // the last tile ends a row too
    val nextY = Mux(lastTile, first, Mux(lastX, tileY + 1, tileY))
    val nextTile = Mux(lastTile, first, tile + 1)

    def write(address: Int, data: Bits): CommandProcessorWrite = {
      val w = CommandProcessorWrite()
      w.addr := address
      w.data := data.resized
      w
    }
    def write(address: Int, data: Int): CommandProcessorWrite =
      write(address, B(data, 32 bits))

    val visBase = Axi4ToApbXbar.visDmaBase
    val tileBase = Axi4ToApbXbar.tileDmaBase
    val frontendBase = Axi4ToApbXbar.frontendBase
    def threadZbufAt(n: Int) =
      Axi4ToApbXbar.threadBase + n * ApbThreadRegs.byteCount + threadZbuf

    // The tile's box: from its first pixel to its last, or the frame's when the tile runs past it
    def boxStart(index: UInt): UInt =
      (index @@ U(0, config.tileShift bits)).resize(16 bits)
    def boxEnd(index: UInt, size: UInt): UInt = {
      val tileEnd =
        (index @@ U(tileSize - 1, config.tileShift bits)).resize(16 bits)
      Mux(tileEnd < size - 1, tileEnd, size - 1)
    }

    val visStartWrite = Vec(write(visBase + visCtrl, visCtrlStart))
    val visAckWrite = Vec(write(visBase + intRaw, intDone))
    val tileAckWrite = Vec(write(tileBase + intRaw, intDone))

    // The write-back, the z-buffer clears with it (other RAMs), then the next tile's setup
    val writeBackWrites = Vec(
      Seq(write(tileBase + tileCtrl, tileCtrlStart)) ++
        (0 until config.threads).map(n => write(threadZbufAt(n), 1)) ++
        Seq(
          write(frontendBase + frontendBbMinX, boxStart(nextX).asBits),
          write(frontendBase + frontendBbMinY, boxStart(nextY).asBits),
          write(frontendBase + frontendBbMaxX, boxEnd(nextX, WIDTH).asBits),
          write(frontendBase + frontendBbMaxY, boxEnd(nextY, HEIGHT).asBits)
        )
    )

    val sequencer = new StateMachine {
      def stop(why: Int): Unit = {
        busy := False
        failed := True
        cause := why
        goto(idle)
      }

      // Sends writes one at a time, then goes to next; stops on an error response
      def sendWrites(
          state: State,
          writes: Vec[CommandProcessorWrite],
          next: => State
      ): Unit = {
        state.onEntry(item := 0)
        state.whenIsActive {
          when(access.done) {
            when(access.error) {
              stop(causeBus)
            }.elsewhen(item === writes.length - 1) {
              goto(next)
            }.otherwise {
              item := item + 1
            }
          }.elsewhen(!access.busy) {
            access.write(writes(item.resized))
          }
        }
      }

      val idle: State = new State with EntryPoint
      val visStart, visWait, visAck, settle, drain, writeBack, writeBackWait,
          tileAck, nextTileState = new State

      idle.whenIsActive {
        when(START && MODE) {
          when(badSize) {
            failed := True
            cause := causeSize
          }.otherwise {
            busy := True
            cause := causeNone
            cycles := 0
            tilesX := tilesXNext.resized
            tilesY := tilesYNext.resized
            tileX := 0
            tileY := 0
            tile := 0
            visError := False
            tileError := False
            frameDone := False
            goto(visStart)
          }
        }
      }

      // 1. The tile's triangles
      visStart.onEntry(
        visDone := False
      ) // the last done is acknowledged: a new edge comes
      sendWrites(visStart, visStartWrite, visWait)

      visWait.whenIsActive {
        when(visError) {
          stop(causeVisDma)
        }.elsewhen(visDone) {
          goto(visAck)
        }
      }

      sendWrites(visAck, visAckWrite, settle)

      // 2. Until everything is empty
      settle.onEntry(waitCycles := 0)
      settle.whenIsActive {
        waitCycles := waitCycles + 1
        when(waitCycles === config.settleCycles - 1) {
          waitCycles := 0
          goto(drain)
        }
      }

      drain.whenIsActive {
        when(!unitsIdle) {
          waitCycles := 0
        }.elsewhen(waitCycles === config.idleCycles - 1) {
          goto(writeBack)
        }.otherwise {
          waitCycles := waitCycles + 1
        }
      }

      // 3. Write-back, clears, the next tile's setup
      writeBack.onEntry {
        tileDone := False
        zbufRose := 0
        zbufDone := 0
      }
      sendWrites(writeBack, writeBackWrites, writeBackWait)

      // 4. Until both are done
      writeBackWait.whenIsActive {
        when(tileError) {
          stop(causeTileDma)
        }.elsewhen(tileDone && zbufDone.andR && (!lastTile || frameDone)) {
          goto(tileAck)
        }
      }

      sendWrites(tileAck, tileAckWrite, nextTileState)

      nextTileState.whenIsActive {
        when(lastTile) {
          busy := False
          finished := True
          goto(idle)
        }.otherwise {
          tileX := nextX
          tileY := nextY
          tile := nextTile
          goto(visStart)
        }
      }
    }
  }

  // Status: a START clears DONE and ERROR (and so does writing 1); the frame then sets one of them
  when(START && MODE && !frame.busy || softReset) {
    DONE := False
    ERROR := False
  }
  when(frame.finished && !softReset)(DONE := True)
  when(frame.failed && !softReset)(ERROR := True)
  BUSY := frame.busy
  CAUSE := frame.cause
  TILE := frame.tile
  FRAME_CYCLES := frame.cycles
  when(frame.busy) {
    MODE := MODE // not changed while BUSY: this assignment comes after the bus's
  }
}

object CommandProcessorVerilog extends App {
  SpinalConfig(
    targetDirectory = "rtl/CommandProcessor",
    defaultConfigForClockDomains = ClockDomainConfig(
      resetActiveLevel = LOW,
      resetKind = SYNC
    )
  ).withPrivateNamespace.generateVerilog(new CommandProcessor())
}
