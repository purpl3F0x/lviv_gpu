package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._
import spinal.lib.fsm._

// =============================================================================
// Tiled RAM (BRAM) Direct Port Interface (Operates in ramClock domain): reads for the write-back,
// and writes that leave CLEAR_VALUE behind them (and fill the RAM on CLEAR)
// =============================================================================
case class TileRamPort(addrWidth: Int, dataWidth: Int) extends Bundle with IMasterSlave {
  val clk = Bool()
  val rst = Bool()
  val en = Bool()
  val addr = UInt(addrWidth bits)
  val dout = Bits(dataWidth bits)
  val wr_en = Bool()
  val wr_addr = UInt(addrWidth bits)
  val wr_data = Bits(dataWidth bits)

  override def asMaster(): Unit = {
    out(clk, rst, en, addr, wr_en, wr_addr, wr_data)
    in(dout)
  }
}

// =============================================================================
// Configuration Bundle for AxiTileDma
// =============================================================================
case class AxiTileDmaConfig(
    addressWidth: Int = 32, // the AXI address and BASE: 17 to 64 bits
    pixelsPerClock: Int = 4, // Number of 32-bit pixels per AXI beat (2, 4, 8, 16); each quad thread port supplies half
    tileWidth: Int = 128, // Tile width in pixels (compile-time constant, e.g. 128)
    tileHeight: Int = 128, // Tile height in rows (compile-time constant, e.g. 128)
    maxBurstLength: Int = 256, // Max AXI burst beats (AXI4 max = 256)
    maxOutstanding: Int = 8, // Max outstanding AXI write transactions
    idWidth: Int = 4, // AXI Master transaction ID width
    cdcDepth: Int = 32, // Depth of async dual-clock CDC FIFO between RAM clock and AXI clock (LUTRAM is 32 deep)
    useAutoAdvance: Boolean = true, // Compile-time option: enable 2D raster tile coordinate advancing
    tileIndexWidth: Int = 8, // TILES_X, TILES_Y and CUR_POS (4096 x 4096 is 32 x 32 tiles)
    bramReadLatency: Int = 1 // Read latency in clock cycles (1 for primitive output reg, 2 for optional pipeline reg)
) {
  require(tileIndexWidth >= 1 && tileIndexWidth <= 16, "tileIndexWidth must be 1 to 16 (CUR_POS's Y is at bit 16)")
  require(addressWidth > 16 && addressWidth <= 64, "addressWidth must be 17 to 64 bits")
  require(pixelsPerClock >= 2 && isPow2(pixelsPerClock), "pixelsPerClock must be a power of 2 >= 2 (2, 4, 8, 16...)")
  require(tileWidth > 0 && tileHeight > 0, "tile dimensions must be positive")
  require(tileWidth % pixelsPerClock == 0, "tileWidth must be an integer multiple of pixelsPerClock")
  require(tileHeight % 2 == 0, "tileHeight must be even (2x2 quad rows)")
  require(maxBurstLength >= 1 && maxBurstLength <= 256, "maxBurstLength must be between 1 and 256 beats")
  require(maxOutstanding >= 1, "maxOutstanding must be at least 1")
  require(cdcDepth >= 8 && isPow2(cdcDepth), "cdcDepth must be a power of 2 >= 8")
  require(bramReadLatency >= 1, "bramReadLatency must be at least 1 clock cycle")

  // BRAM read latency + 1 register stage for the quad interleave mux
  val readPipeLatency: Int = bramReadLatency + 1

  val pixelBits: Int = 32
  val pixelBytes: Int = 4
  val dataWidth: Int = pixelsPerClock * pixelBits
  val bytesPerBeat: Int = pixelsPerClock * pixelBytes
  val beatShift: Int = log2Up(bytesPerBeat)

  // Compile-time tile geometry (128x128 tile)
  val tileHeightShift: Int = log2Up(tileHeight) // 7 bits for 128 rows
  val tileWidthShift: Int = log2Up(tileWidth) // 7 bits for 128 cols
  val beatsPerRow: Int = tileWidth / pixelsPerClock
  val totalBeats: Int = beatsPerRow * tileHeight
  val bytesPerRow: Int = tileWidth * pixelBytes
  val totalBytes: Int = tileWidth * tileHeight * pixelBytes

  // 4KB-aligned base + STRIDE multiple of bytesPerRow => every tile line starts on a bytesPerRow
  // boundary and fits in one 4KB page, so all AXI bursts have the same length and never cross 4KB
  require(isPow2(bytesPerRow) && bytesPerRow <= 4096, "tile row bytes must be a power of 2 <= 4KB")
  val strideAlignShift: Int = log2Up(bytesPerRow) // STRIDE must be a multiple of bytesPerRow (512 B)
  val baseAlignShift: Int = strideAlignShift + tileIndexWidth // BASE's alignment: 17 bits, 128 KiB
  require(baseAlignShift >= 12 && baseAlignShift <= 32, "BASE's alignment must be 4KB to 4GB")
  val burstBeats: Int = beatsPerRow min maxBurstLength
  require(beatsPerRow % burstBeats == 0, "beatsPerRow must be a multiple of maxBurstLength when longer")
  val burstsPerRow: Int = beatsPerRow / burstBeats
  val burstBytes: Int = burstBeats * bytesPerBeat

  // GPU 2x2 quad thread RAMs:
  //   thread 0 = (even x, even y), thread 1 = (odd x, even y)
  //   thread 2 = (even x, odd y),  thread 3 = (odd x, odd y)
  // Each thread RAM word holds that thread's pixel from threadPixels horizontally consecutive quads,
  // one word row per quad row (tileHeight / 2 rows of beatsPerRow words).
  val quadThreads: Int = 4
  val threadPixels: Int = pixelsPerClock / 2
  val threadDataWidth: Int = threadPixels * pixelBits // 64 bits @ 4 px/clock
  val threadBytesPerBeat: Int = threadPixels * pixelBytes
  val threadBeatShift: Int = log2Up(threadBytesPerBeat)
  val threadTotalBeats: Int = beatsPerRow * (tileHeight / 2)
  val threadTotalBytes: Int = threadTotalBeats * threadBytesPerBeat
  val threadWordAddrWidth: Int = log2Up(threadTotalBeats) max 1
  val threadByteAddrWidth: Int = log2Up(threadTotalBytes) max 1 // Byte-addressable BRAM address width

  def getAxi4Config: Axi4Config = Axi4Config(
    addressWidth = addressWidth,
    dataWidth = dataWidth,
    idWidth = idWidth,
    useBurst = true,
    useSize = true,
    useLen = true,
    useLast = true,
    useResp = true,
    useStrb = true,
    useId = idWidth > 0
  )

  def getApbConfig: Apb3Config = Apb3Config(
    addressWidth = 7,
    dataWidth = 32
  )
}

// =============================================================================
// 2D Tile Frame Buffer DMA Module (Dual Clock Domains with Async CDC FIFO)
// =============================================================================
class AxiTileDma(
    val config: AxiTileDmaConfig,
    val ramClockDomain: ClockDomain = null
) extends Component {

  // High-frequency BRAM clock domain
  val ramClock = if (ramClockDomain != null) ramClockDomain else ClockDomain.external("ram", withReset = true)

  val io = new Bundle {
    // 1. APB3 Slave Interface for Register Programming (AXI clock domain)
    val s_apb = slave(Apb3(config.getApbConfig))

    // 2. AXI4 Full Write Master Interface to DRAM (AXI clock domain)
    val m_axi = master(Axi4WriteOnly(config.getAxi4Config))

    // 3. Per-thread 2x2 quad Tiled RAM (BRAM) Ports (Operate in high-frequency ramClock domain)
    val tile_ram =
      Vec.fill(config.quadThreads)(master(TileRamPort(config.threadByteAddrWidth, config.threadDataWidth)))

    // 4. Interrupt Outputs (AXI clock domain)
    val irq = out Bool ()
    val irq_done = out Bool ()
    val irq_error = out Bool ()
    val irq_frame_done = out Bool ()
  }

  // Clear top-level "io_" prefix for clean Verilog / EDA naming
  noIoPrefix()

  // Vivado AXI standard bus port renaming helper
  def renameAxiForVivado(bundle: Bundle, prefix: String): Unit = {
    bundle.flatten.foreach { signal =>
      val name = signal.getName()
      val cleanName = name
        .replaceFirst("^io_", "")
        .replace(s"${prefix}_", "")
        .replace("_payload_", "")
        .replace("_payload", "")
        .replace("_", "")

      signal.setName(s"${prefix}_${cleanName}")
    }
  }

  renameAxiForVivado(io.m_axi, "m_axi")

  // Forward RAM clock and active-high reset to each thread RAM port
  // Input ram_resetn is active-low, but tile_ram_N_rst is ALWAYS active-high
  for (port <- io.tile_ram) {
    port.clk := ramClock.readClockWire
    port.rst := !ramClock.readResetWire
  }

  // AXI Clock and Reset names & Vivado interface association attributes
  // Attributes go on the pulled-in wires (readClockWire/readResetWire), which are this component's ports
  clockDomain.clock.setName("aclk")
  clockDomain.reset.setName("aresetn")
  clockDomain.readClockWire
    .setName("aclk")
    .addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:clock:1.0 aclk CLK")
    .addAttribute("X_INTERFACE_PARAMETER", "ASSOCIATED_BUSIF m_axi, ASSOCIATED_RESET aresetn")
  clockDomain.readResetWire
    .setName("aresetn")
    .addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:reset:1.0 aresetn RST")
    .addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")

  // RAM Clock and Reset names & Vivado attributes (input reset is active-low ram_resetn)
  ramClock.clock.setName("ram_clk")
  ramClock.reset.setName("ram_resetn")
  ramClock.readClockWire
    .setName("ram_clk")
    .addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:clock:1.0 ram_clk CLK")
    .addAttribute("X_INTERFACE_PARAMETER", "ASSOCIATED_RESET ram_resetn")
  ramClock.readResetWire
    .setName("ram_resetn")
    .addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:reset:1.0 ram_resetn RST")
    .addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")

  // Vivado Interrupt interface attributes
  io.irq.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq INTERRUPT")
  io.irq.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_done.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_done INTERRUPT")
  io.irq_done.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_error.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_error INTERRUPT")
  io.irq_error.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_frame_done.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_frame_done INTERRUPT")
  io.irq_frame_done.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")

  // ===========================================================================
  // AXI CLOCK DOMAIN LOGIC
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Register Map via SpinalHDL Built-in regif
  // ---------------------------------------------------------------------------
  val busif = Apb3BusInterface(io.s_apb, (0x0000, 128), "AXI_TILE_DMA")

  // Status and Debug registers driven by hardware
  val dmaBusy = RegInit(False)
  val softResetPending = RegInit(False)
  val brespVal = Reg(Bits(2 bits)) init (0)
  val curLineIdx = Reg(UInt(log2Up(config.tileHeight + 1) bits)) init (0)
  val cycleCounter = Reg(UInt(32 bits)) init (0)

  // 0x00: CONTROL
  val REG_CTRL = busif.newRegAt(address = 0x00, doc = "DMA Control Register")
  val START = REG_CTRL.field(Bool(), W1P, doc = "Trigger 128x128 tile transfer to DRAM")
  val RESET_POS =
    if (config.useAutoAdvance) REG_CTRL.field(Bool(), W1P, doc = "Reset tile coordinates (TileX=0, TileY=0)") else null
  if (!config.useAutoAdvance) REG_CTRL.reserved(1 bits)
  val SOFT_RESET = REG_CTRL.field(
    Bool(),
    W1P,
    doc = "Software reset for DMA FSM and tile position (deferred until the active transfer completes)"
  )
  val CLEAR = REG_CTRL.field(
    Bool(),
    W1P,
    doc = "Fill the four tile RAMs with CLEAR_VALUE, STATUS.CLEAR_BUSY until done (ignored while BUSY or CLEAR_BUSY)"
  )

  // 0x04: STATUS (Operational status flags; interrupt events managed by INTR factory at 0x40)
  val REG_STATUS = busif.newRegAt(address = 0x04, doc = "DMA Status Register")
  val BUSY = REG_STATUS.field(Bool(), RO, doc = "DMA active transfer busy flag")
  val LAST_BRESP = REG_STATUS.field(Bits(2 bits), RO, doc = "Last AXI write response status")
  val SOFT_RESET_PENDING =
    REG_STATUS.field(Bool(), RO, doc = "Soft reset requested, waiting for the active transfer to complete")
  val CLEAR_BUSY = REG_STATUS.field(Bool(), RO, doc = "CLEAR in progress (START is ignored meanwhile)")

  BUSY := dmaBusy
  LAST_BRESP := brespVal
  SOFT_RESET_PENDING := softResetPending
  val clearBusy = RegInit(False)
  CLEAR_BUSY := clearBusy

  // 0x08: BASE_ADDR_LOW (RW) - bits below baseAlignShift reserved: BASE is that aligned
  val REG_BASE_LOW = busif.newRegAt(address = 0x08, doc = "DRAM Frame Base Address (Lower 32 bits)")
  val BASE_ADDR_LOW = REG_BASE_LOW.fieldAt(
    pos = config.baseAlignShift,
    UInt(32 - config.baseAlignShift bits),
    RW,
    resetValue = 0,
    doc = s"Bits 31..${config.baseAlignShift} of Frame Destination Base Address " +
      s"(${(1 << config.baseAlignShift) >> 10} KiB aligned)"
  )

  // 0x0C: BASE_ADDR_HIGH (RW), all reserved with 32-bit addresses
  val REG_BASE_HIGH = busif.newRegAt(address = 0x0c, doc = "DRAM Frame Base Address (Upper bits)")
  val BASE_ADDR_HIGH =
    if (config.addressWidth > 32)
      REG_BASE_HIGH.field(
        UInt(config.addressWidth - 32 bits),
        RW,
        resetValue = 0,
        doc = s"Bits ${config.addressWidth - 1}..32 of Frame Base Address (${config.addressWidth}-bit DRAM space)"
      )
    else {
      REG_BASE_HIGH.reserved(32 bits)
      null
    }

  // 0x10: STRIDE (RW)
  val REG_STRIDE = busif.newRegAt(address = 0x10, doc = "DRAM Frame Row Byte Stride")
  val STRIDE =
    REG_STRIDE.field(
      UInt(32 bits),
      RW,
      resetValue = 0,
      doc = s"Framebuffer row byte stride / pitch (multiple of ${config.bytesPerRow} bytes, low bits ignored)"
    )

  // 0x14: TILES_X
  val REG_TILES_X = if (config.useAutoAdvance) busif.newRegAt(address = 0x14, doc = "Horizontal Tiles Count") else null
  val TILES_X =
    if (config.useAutoAdvance)
      REG_TILES_X.field(
        UInt(config.tileIndexWidth bits),
        RW,
        resetValue = 1,
        doc = "Total number of horizontal tiles per frame row"
      )
    else null

  // 0x18: TILES_Y
  val REG_TILES_Y =
    if (config.useAutoAdvance) busif.newRegAt(address = 0x18, doc = "Vertical Tile Rows Count") else null
  val TILES_Y =
    if (config.useAutoAdvance)
      REG_TILES_Y.field(
        UInt(config.tileIndexWidth bits),
        RW,
        resetValue = 1,
        doc = "Total number of vertical tile rows per frame"
      )
    else null

  // 0x1C: CUR_POS (RW) - Bits 7..0 = curTileX, bits 23..16 = curTileY: the tile START writes
  val REG_CUR_POS = if (config.useAutoAdvance) busif.newRegAt(address = 0x1c, doc = "Current Tile Position") else null
  val CUR_TILE_X =
    if (config.useAutoAdvance)
      REG_CUR_POS.field(
        UInt(config.tileIndexWidth bits),
        RW,
        resetValue = 0,
        doc = "Current horizontal tile index (0..TILES_X-1)"
      )
    else null
  val CUR_TILE_Y =
    if (config.useAutoAdvance)
      REG_CUR_POS.fieldAt(
        pos = 16,
        UInt(config.tileIndexWidth bits),
        RW,
        resetValue = 0,
        doc = "Current vertical tile row index (0..TILES_Y-1)"
      )
    else null

  // 0x20: CURRENT_LINE (RO)
  val REG_LINE = busif.newRegAt(address = 0x20, doc = "Current Line Progress")
  val CURRENT_LINE =
    REG_LINE.field(
      UInt(log2Up(config.tileHeight + 1) bits),
      RO,
      doc = s"Line index being issued on AXI AW within active tile (0..${config.tileHeight - 1})"
    )
  CURRENT_LINE := curLineIdx

  // 0x24: PERF_CYCLES (RO)
  val REG_PERF = busif.newRegAt(address = 0x24, doc = "Performance Cycle Counter")
  val PERF_CYCLES = REG_PERF.field(UInt(32 bits), RO, doc = "Elapsed clock cycles during active tile transfer")
  PERF_CYCLES := cycleCounter

  // 0x28: CLEAR_VALUE (RW)
  val REG_CLEAR_VALUE = busif.newRegAt(address = 0x28, doc = "Tile RAM Clear Value")
  val CLEAR_VALUE = REG_CLEAR_VALUE.field(
    Bits(32 bits),
    RW,
    resetValue = 0,
    doc = "Pixel left in the tile RAMs: written over each word the transfer has read, and by CLEAR"
  )

  // ===========================================================================
  // INTERRUPT FACTORY REGISTERS (0x40 - 0x4C)
  // RegGroup RFMS4:
  //   0x40: INTR_INT_RAW    - Raw interrupt event flags (W1C: write 1 to clear)
  //   0x44: INTR_INT_FORCE  - Software debug force (W1S: write 1 to trigger raw)
  //   0x48: INTR_INT_MASK   - Mask register (RW: 1 = masked/off, 0 = unmasked/open)
  //   0x4C: INTR_INT_STATUS - Masked status register (RO: raw && !mask)
  // Fields:
  //   Bit 0: done           - Tile transfer complete
  //   Bit 1: error          - AXI bus write error (SLVERR/DECERR)
  //   Bit 2: frame_done     - Final tile of frame complete (Auto-Advance wrap)
  // ===========================================================================
  val intrDone = False
  val intrError = False
  val intrFrameDone = False

  val INTR = busif.newIntrRFMS4(addr = 0x40, doc = "DMA Interrupt Controller")
  val irqDoneStat =
    INTR.fieldAt(0, intrDone, maskRstVal = 0, doc = "Tile done interrupt (1: unmasked/open)")(SymbolName("done"))
  val irqErrorStat =
    INTR.fieldAt(1, intrError, maskRstVal = 0, doc = "Error interrupt (1: unmasked/open)")(SymbolName("error"))
  val irqFrameDoneStat = if (config.useAutoAdvance) {
    INTR.fieldAt(2, intrFrameDone, maskRstVal = 0, doc = "Frame done interrupt (1: unmasked/open)")(
      SymbolName("frame_done")
    )
  } else null

  val irqMerged = INTR.intr()

  // Built-in Documentation & Header Generators (exported to targetDirectory)
  busif.accept(HtmlGenerator("axi_tile_dma_regmap", "AXI_TILE_DMA"))
  busif.accept(CHeaderGenerator("axi_tile_dma_regmap", "AXI_TILE_DMA"))
  busif.accept(JsonGenerator("axi_tile_dma_regmap"))

  // Frame base address (bits below baseAlignShift are 0)
  val fullBaseAddr = UInt(config.addressWidth bits)
  if (config.addressWidth > 32) {
    fullBaseAddr := BASE_ADDR_HIGH @@ BASE_ADDR_LOW @@ U(0, config.baseAlignShift bits)
  } else {
    fullBaseAddr := (BASE_ADDR_LOW @@ U(0, config.baseAlignShift bits)).resized
  }

  // ---------------------------------------------------------------------------
  // 2D Raster Tile Position & Origin
  // ---------------------------------------------------------------------------
  // Tile origin = BASE + X * 512 + Y * STRIDE * 128 (X, Y = CUR_TILE_X, CUR_TILE_Y), on one DSP:
  //
  //   bit 47          17  16  15        9  8       0
  //      +--------------+----+-----------+----------+
  //      | BASE[47:17]  | X7 |  X[6:0]   |    0     |   BASE (128 KiB aligned) and X, concatenated
  //      +--------------+----+-----------+----------+
  //      |<------ C -------->|<-------- low -------->|
  //    +   (STRIDE/512) * Y                             A * B
  //    =   P = C + A * B       low                      origin
  //
  // No reset on these registers, so synthesis maps them into the DSP's.
  val strideUnitWidth: Int = 32 - config.strideAlignShift
  val rowShift: Int = config.strideAlignShift + config.tileHeightShift // 16: C and P start at this bit
  val dspA = if (config.useAutoAdvance) Reg(UInt(strideUnitWidth bits)) else null
  val dspB = if (config.useAutoAdvance) Reg(UInt(config.tileIndexWidth bits)) else null
  val dspC = if (config.useAutoAdvance) Reg(UInt(config.addressWidth - rowShift bits)) else null
  val dspM = if (config.useAutoAdvance) Reg(UInt(strideUnitWidth + config.tileIndexWidth bits)) else null
  val dspP = if (config.useAutoAdvance) Reg(UInt(config.addressWidth - rowShift bits)) else null
  val originLow = if (config.useAutoAdvance) Reg(UInt(rowShift bits)) else null

  val shadowStride = Reg(UInt(32 bits)) init (0)
  val shadowTilesX = if (config.useAutoAdvance) Reg(UInt(config.tileIndexWidth bits)) init (1) else null
  val shadowTilesY = if (config.useAutoAdvance) Reg(UInt(config.tileIndexWidth bits)) init (1) else null

  if (config.useAutoAdvance) {
    // Reset tile position to (0,0)
    when(RESET_POS) {
      CUR_TILE_X := 0
      CUR_TILE_Y := 0
    }
  }

  when(dmaBusy) {
    cycleCounter := cycleCounter + 1
  }

  // ---------------------------------------------------------------------------
  // Asynchronous Dual-Clock CDC FIFO (ramClock -> axiClock)
  // ---------------------------------------------------------------------------
  val cdcFifo = StreamFifoCC(
    dataType = Bits(config.dataWidth bits),
    depth = config.cdcDepth,
    pushClock = ramClock,
    popClock = ClockDomain.current // axiClock
  )
  cdcFifo.ram.addAttribute("ram_style", "distributed")

  // Pulse to start reading the 128x128 tile in the high-frequency ramClock domain
  val startTilePulseAxi = False

  // Cross single-cycle start pulse from AXI domain to RAM domain
  val startPulseRam = PulseCCByToggle(
    input = startTilePulseAxi,
    clockIn = ClockDomain.current,
    clockOut = ramClock
  )

  // Pulse to fill the tile RAMs with CLEAR_VALUE (CLEAR) in the ramClock domain
  val clearPulseAxi = False
  val clearPulseRam = PulseCCByToggle(
    input = clearPulseAxi,
    clockIn = ClockDomain.current,
    clockOut = ramClock
  )

  // CLEAR_VALUE as of the accepted START or CLEAR. It only changes then, and the pulse takes at least
  // two ramClock cycles to cross, so the RAM domain takes it on the pulse without synchronizers.
  val clearValueShadow = Reg(Bits(32 bits)) init (0)
  clearValueShadow.addTag(crossClockDomain)

  // ===========================================================================
  // HIGH-FREQUENCY RAM CLOCK DOMAIN LOGIC (ramClock, optimized for 600+ MHz)
  // Fully pipelined credit tracking: registers pushOccupancy to cut the Gray-to-Binary
  // XOR path, and drives tile_ram_N.en and tile_ram_N.addr directly from registers.
  //
  // 2x2 quad readout: all four thread RAMs share one word address. Even tile lines take
  // threads 0/1, then the same quad row is re-read for the odd line from threads 2/3.
  // Each 128-bit beat interleaves the pair as (L.p0, R.p0, L.p1, R.p1, ...).
  // ===========================================================================
  val ramArea = new ClockingArea(ramClock) {
    val ramReadsLeft = Reg(UInt(log2Up(config.totalBeats + 1) bits)) init (0)
    val ramPushesLeft = Reg(UInt(log2Up(config.totalBeats + 1) bits)) init (0)
    val ramAddrReg = Reg(UInt(config.threadWordAddrWidth bits)) init (0)
    val ramRowBase = Reg(UInt(config.threadWordAddrWidth bits)) init (0) // First word of current quad row
    val ramBeatX = Reg(UInt(log2Up(config.beatsPerRow) max 1 bits)) init (0)
    val ramOddLine = RegInit(False) // False: threads 0/1 (even line), True: threads 2/3 (odd line)
    val ramEnReg = RegInit(False)
    val active = RegInit(False)

    // Pipeline Stage 1: Register CDC FIFO push occupancy to isolate the popToPushGray XOR path
    val pushOccupancyReg = RegNext(cdcFifo.io.pushOccupancy) init (0)

    // In-flight tracking: counts reads in pipeline between schedule and retirement into pushOccupancyReg
    // Sized to cdcDepth + 1 to prevent counter overflow during bursts
    val inFlight = Reg(UInt(log2Up(config.cdcDepth + 1) bits)) init (0)
    val inFlightRetire = Delay(ramEnReg, cycleCount = config.readPipeLatency + 2, init = False)

    // Pipeline Stage 2: comparison with registered occupancy. Every entry is usable: a read stays in
    // inFlight until pushOccupancyReg shows it, and pops reach this side late, so the count is never low.
    val totalCommitted = pushOccupancyReg + inFlight
    val hasRoom = totalCommitted < config.cdcDepth
    val nextCanRead = active && (ramReadsLeft > 0) && hasRoom

    // Direct Register Outputs to BRAM pins (Zero combinational gates, optimal for 600 MHz)
    // BRAM is continuously enabled throughout active transfer; disabled when idle
    for (port <- io.tile_ram) {
      port.en := active
      port.addr := (ramAddrReg @@ U(0, config.threadBeatShift bits)).resized
    }

    // Delay read enable and line parity by bramReadLatency cycles to align with BRAM dout valid timing
    val readValid = Delay(ramEnReg, cycleCount = config.bramReadLatency, init = False)
    val readOddLine = Delay(ramOddLine, cycleCount = config.bramReadLatency, init = False)

    // Select the thread pair for this line and interleave their pixels into one AXI beat
    val leftWord = readOddLine ? io.tile_ram(2).dout | io.tile_ram(0).dout
    val rightWord = readOddLine ? io.tile_ram(3).dout | io.tile_ram(1).dout
    val mergedWord = Bits(config.dataWidth bits)
    for (i <- 0 until config.threadPixels) {
      mergedWord((2 * i) * config.pixelBits, config.pixelBits bits) := leftWord(
        i * config.pixelBits,
        config.pixelBits bits
      )
      mergedWord((2 * i + 1) * config.pixelBits, config.pixelBits bits) := rightWord(
        i * config.pixelBits,
        config.pixelBits bits
      )
    }

    // Register the interleave mux output before the CDC FIFO write port
    val mergedValid = RegNext(readValid) init (False)
    val mergedData = RegNext(mergedWord)

    // CLEAR_VALUE in every pixel of a word
    val clearWord = RegNextWhen(Cat(Seq.fill(config.threadPixels)(clearValueShadow)), startPulseRam || clearPulseRam)

    // CLEAR: every word of all four RAMs, one per cycle
    val clearing = RegInit(False)
    val clearAddr = Reg(UInt(config.threadWordAddrWidth bits)) init (0)
    val clearLastWord = clearing && clearAddr === config.threadTotalBeats - 1
    when(clearPulseRam) {
      clearing := True
      clearAddr := 0
    }.elsewhen(clearing) {
      clearAddr := clearAddr + 1
      when(clearLastWord) {
        clearing := False
      }
    }
    // Done once the last word is in the RAMs: a cycle to the write registers, two in the RAM
    val clearDone = Delay(clearLastWord, cycleCount = 4, init = False)

    // Writes, straight from registers, a cycle after the read they follow:
    //  - in a transfer, the word just read, in the two RAMs its line used (threads 0/1 on an even
    //    line, 2/3 on an odd one, so the odd line's re-read of the quad row still finds threads 2/3).
    //    In a RAM that registers writes and reads alike (frame_buffer_ram: the write lands two edges
    //    after its request, the array read two edges after its), the write lands an edge after the
    //    array read of the word, while the array reads the next word: a word is never read and
    //    written on the same edge.
    //  - in CLEAR, every word of all four
    val wrEnReg = Vec.fill(config.quadThreads)(RegInit(False))
    val wrAddrReg = Reg(UInt(config.threadWordAddrWidth bits)) init (0)
    for (t <- 0 until config.quadThreads) {
      val lineUsesThread = if (t < 2) !ramOddLine else ramOddLine
      wrEnReg(t) := clearing || (ramEnReg && lineUsesThread)
    }
    wrAddrReg := clearing ? clearAddr | ramAddrReg
    for ((port, t) <- io.tile_ram.zipWithIndex) {
      port.wr_en := wrEnReg(t)
      port.wr_addr := (wrAddrReg @@ U(0, config.threadBeatShift bits)).resized
      port.wr_data := clearWord
    }

    when(startPulseRam) {
      ramReadsLeft := config.totalBeats
      ramPushesLeft := config.totalBeats
      ramAddrReg := 0
      ramRowBase := 0
      ramBeatX := 0
      ramOddLine := False
      ramEnReg := False
      inFlight := 0
      active := True
    }.otherwise {
      // Register read enable for cycle T+1
      ramEnReg := nextCanRead

      // Address advances whenever a read is active
      when(ramEnReg) {
        when(ramBeatX === config.beatsPerRow - 1) {
          ramBeatX := 0
          ramOddLine := !ramOddLine
          when(ramOddLine) {
            // Odd line done: quad row complete, step to the next quad row
            ramAddrReg := ramAddrReg + 1
            ramRowBase := ramAddrReg + 1
          }.otherwise {
            // Even line done: rewind to re-read this quad row from threads 2/3
            ramAddrReg := ramRowBase
          }
        }.otherwise {
          ramBeatX := ramBeatX + 1
          ramAddrReg := ramAddrReg + 1
        }
      }

      // Reads remaining decrements when a read is scheduled
      when(nextCanRead) {
        ramReadsLeft := ramReadsLeft - 1
      }

      // In-flight read tracking: increment on schedule, decrement on retirement into pushOccupancyReg
      when(nextCanRead =/= inFlightRetire) {
        when(nextCanRead) {
          inFlight := inFlight + 1
        }.otherwise {
          when(inFlight > 0) {
            inFlight := inFlight - 1
          }
        }
      }

      // Pushes remaining decrements when data enters CDC FIFO
      when(mergedValid) {
        ramPushesLeft := ramPushesLeft - 1
      }

      // Deassert active when all beats have entered CDC FIFO
      when(active && ramPushesLeft === 0) {
        active := False
      }
    }

    // Push interleaved quad data into the dual-clock CDC FIFO
    cdcFifo.io.push.valid := mergedValid
    cdcFifo.io.push.payload := mergedData
  }

  // CLEAR finished, back in the AXI domain
  val clearDoneAxi = PulseCCByToggle(
    input = ramArea.clearDone,
    clockIn = ramClock,
    clockOut = ClockDomain.current
  )
  when(clearDoneAxi) {
    clearBusy := False
  }

  // ===========================================================================
  // AXI4 MASTER WRITE CHANNELS & FSM LOGIC (axiClock domain)
  //
  // Base is 4KB aligned and STRIDE is a multiple of bytesPerRow (512 B), so every tile line
  // starts on a bytesPerRow boundary and lies inside one 4KB page: all bursts are the same
  // compile-time length (burstBeats) and never need 4KB splitting.
  //
  // With auto-advance, START writes the tile at CUR_POS (in any order), then ADVANCE moves it on.
  //
  // AW and W are decoupled:
  //   - The AW planner issues bursts ahead of the data, up to maxOutstanding bursts
  //     awaiting their B response.
  //   - The W engine streams beats from the CDC FIFO back-to-back, gated by wCredits
  //     (bursts whose AW was accepted but whose W beats are not yet complete).
  // ===========================================================================
  object DmaState extends SpinalEnum {
    val IDLE, TRANSFER = newElement()
    val ORIGIN_MUL = if (config.useAutoAdvance) newElement() else null
    val ORIGIN_ADD = if (config.useAutoAdvance) newElement() else null
    val ORIGIN_LOAD = if (config.useAutoAdvance) newElement() else null
    val ADVANCE = if (config.useAutoAdvance) newElement() else null
  }
  val state = RegInit(DmaState.IDLE)

  // ---------------------------------------------------------------------------
  // AW Burst Planner
  // ---------------------------------------------------------------------------
  val planActive = RegInit(False) // More bursts left to issue for the active tile
  val planLineStart = Reg(UInt(config.addressWidth bits)) init (0)
  val planAddr = Reg(UInt(config.addressWidth bits)) init (0)
  val planBurstIdx = Reg(UInt(log2Up(config.burstsPerRow) max 1 bits)) init (0) // Burst index within line

  // Counts bursts from planner load until B response
  val outstandingBursts = Reg(UInt(log2Up(config.maxOutstanding + 1) bits)) init (0)

  val planLastBurstInLine = if (config.burstsPerRow == 1) True else planBurstIdx === (config.burstsPerRow - 1)
  val planLastLine = curLineIdx === (config.tileHeight - 1)

  // AW output stage (registered AXI outputs)
  val awValidReg = RegInit(False)
  val awAddrReg = Reg(UInt(config.addressWidth bits)) init (0)

  // Load next burst when the AW stage is free (or draining) and the outstanding budget allows
  val planLoad = (state === DmaState.TRANSFER) && planActive &&
    (outstandingBursts < config.maxOutstanding) && (!awValidReg || io.m_axi.aw.ready)

  when(planLoad) {
    awValidReg := True
    awAddrReg := planAddr

    when(planLastBurstInLine) {
      planBurstIdx := 0
      when(planLastLine) {
        // Last burst of the tile issued
        planActive := False
      }.otherwise {
        // Advance to next line within current tile (single register addition)
        val nextLineDram = planLineStart + shadowStride.resized
        planLineStart := nextLineDram
        planAddr := nextLineDram
        curLineIdx := curLineIdx + 1
      }
    }.otherwise {
      // More bursts remaining in current line (line longer than maxBurstLength)
      planBurstIdx := planBurstIdx + 1
      planAddr := planAddr + U(config.burstBytes, config.addressWidth bits)
    }
  }.elsewhen(io.m_axi.aw.ready) {
    awValidReg := False
  }

  // ---------------------------------------------------------------------------
  // AXI4 AW (Write Address) Channel
  // ---------------------------------------------------------------------------
  io.m_axi.aw.valid := awValidReg
  io.m_axi.aw.addr := awAddrReg
  io.m_axi.aw.len := U(config.burstBeats - 1, 8 bits)
  io.m_axi.aw.size := U(config.beatShift, 3 bits)
  io.m_axi.aw.burst := Axi4.burst.INCR

  if (config.idWidth > 0) io.m_axi.aw.id.clearAll()
  if (config.getAxi4Config.useRegion) io.m_axi.aw.region.clearAll()
  if (config.getAxi4Config.useLock) io.m_axi.aw.lock.clearAll()
  if (config.getAxi4Config.useCache) io.m_axi.aw.cache := B"0011"
  if (config.getAxi4Config.useProt) io.m_axi.aw.prot.clearAll()
  if (config.getAxi4Config.useQos) io.m_axi.aw.qos.clearAll()

  val awFire = io.m_axi.aw.fire

  // ---------------------------------------------------------------------------
  // AXI4 W (Write Data) Channel - Pop from Async CDC FIFO
  // ---------------------------------------------------------------------------
  val wCredits = Reg(UInt(log2Up(config.maxOutstanding + 1) bits)) init (0)
  val wBeatIdx = Reg(UInt(log2Up(config.burstBeats) max 1 bits)) init (0) // Beat index within burst
  val wLast = if (config.burstBeats == 1) True else wBeatIdx === (config.burstBeats - 1)
  val wFire = io.m_axi.w.fire
  val wBurstDone = wFire && wLast

  io.m_axi.w.valid := (wCredits =/= 0) && cdcFifo.io.pop.valid
  io.m_axi.w.data := cdcFifo.io.pop.payload
  io.m_axi.w.strb.setAll()
  io.m_axi.w.last := wLast

  cdcFifo.io.pop.ready := (wCredits =/= 0) && io.m_axi.w.ready

  when(wFire) {
    wBeatIdx := wLast ? U(0, wBeatIdx.getWidth bits) | (wBeatIdx + 1)
  }

  when(awFire && !wBurstDone) {
    wCredits := wCredits + 1
  }.elsewhen(!awFire && wBurstDone) {
    wCredits := wCredits - 1
  }

  // ---------------------------------------------------------------------------
  // AXI4 B (Write Response) Channel
  // ---------------------------------------------------------------------------
  io.m_axi.b.ready := True

  val bFire = io.m_axi.b.fire

  when(planLoad && !bFire) {
    outstandingBursts := outstandingBursts + 1
  }.elsewhen(!planLoad && bFire) {
    outstandingBursts := outstandingBursts - 1
  }

  when(bFire) {
    when(io.m_axi.b.resp === Axi4.resp.SLVERR || io.m_axi.b.resp === Axi4.resp.DECERR) {
      intrError := True
      brespVal := io.m_axi.b.resp
    }
  }

  // ---------------------------------------------------------------------------
  // Main DMA FSM Control (AXI Clock Domain)
  // SOFT_RESET is deferred until IDLE: issued AXI bursts cannot be aborted and the
  // RAM reader / CDC FIFO must drain, so a request during a transfer is held pending.
  // ---------------------------------------------------------------------------
  when(SOFT_RESET) {
    softResetPending := True
  }

  switch(state) {
    is(DmaState.IDLE) {
      when(SOFT_RESET || softResetPending) {
        softResetPending := False
        if (config.useAutoAdvance) {
          CUR_TILE_X := 0
          CUR_TILE_Y := 0
        }
      }.elsewhen(CLEAR && !clearBusy) {
        clearBusy := True
        clearValueShadow := CLEAR_VALUE
        clearPulseAxi := True
      }.elsewhen(START && !dmaBusy && !clearBusy) {
        dmaBusy := True
        cycleCounter := 0
        clearValueShadow := CLEAR_VALUE

        shadowStride := STRIDE(31 downto config.strideAlignShift) @@ U(0, config.strideAlignShift bits)
        if (config.useAutoAdvance) {
          shadowTilesX := (TILES_X === 0) ? U(1, config.tileIndexWidth bits) | TILES_X
          shadowTilesY := (TILES_Y === 0) ? U(1, config.tileIndexWidth bits) | TILES_Y
          // The DSP's operands (see the origin diagram)
          val baseColumn = fullBaseAddr(config.addressWidth - 1 downto config.baseAlignShift) @@ CUR_TILE_X @@
            U(0, config.strideAlignShift bits)
          dspA := STRIDE(31 downto config.strideAlignShift)
          dspB := CUR_TILE_Y
          dspC := baseColumn(config.addressWidth - 1 downto rowShift)
          originLow := baseColumn(rowShift - 1 downto 0)
          state := DmaState.ORIGIN_MUL
        } else {
          planLineStart := fullBaseAddr
          planAddr := fullBaseAddr
          state := DmaState.TRANSFER
        }

        curLineIdx := 0
        planBurstIdx := 0
        planActive := True

        // Trigger high-frequency RAM reader in ramClock domain via CDC pulse
        startTilePulseAxi := True
      }
    }

    if (config.useAutoAdvance) {
      // The origin on the DSP: A * B, C + A * B, then {P, low}
      is(DmaState.ORIGIN_MUL) {
        dspM := dspA * dspB
        state := DmaState.ORIGIN_ADD
      }

      is(DmaState.ORIGIN_ADD) {
        dspP := dspC + dspM.resize(config.addressWidth - rowShift bits)
        state := DmaState.ORIGIN_LOAD
      }

      is(DmaState.ORIGIN_LOAD) {
        planLineStart := dspP @@ originLow
        planAddr := dspP @@ originLow
        state := DmaState.TRANSFER
      }
    }

    is(DmaState.TRANSFER) {
      // All bursts issued and every B response received (B implies all W beats sent)
      when(!planActive && outstandingBursts === 0) {
        if (config.useAutoAdvance) {
          // done/BUSY are reported in ADVANCE, together with the new position and frame_done
          state := DmaState.ADVANCE
        } else {
          dmaBusy := False
          intrDone := True
          state := DmaState.IDLE
        }
      }
    }

    if (config.useAutoAdvance) {
      // Next tile: right, the next row, or (0, 0) with frame_done
      is(DmaState.ADVANCE) {
        when(CUR_TILE_X === shadowTilesX - 1) {
          CUR_TILE_X := 0
          when(CUR_TILE_Y === shadowTilesY - 1) {
            CUR_TILE_Y := 0
            intrFrameDone := True
          }.otherwise {
            CUR_TILE_Y := CUR_TILE_Y + 1
          }
        }.otherwise {
          CUR_TILE_X := CUR_TILE_X + 1
        }

        dmaBusy := False
        intrDone := True
        state := DmaState.IDLE
      }
    }
  }

  // Discrete status & interrupt outputs
  val rawBits = INTR.RAW.readBits
  io.irq := irqMerged
  io.irq_done := rawBits(0)
  io.irq_error := rawBits(1)
  io.irq_frame_done := (if (config.useAutoAdvance) rawBits(2) else False)
}

// =============================================================================
// Helper: Optional Top-Level Wrapper with Integrated 128x128 Tile Dual-Port BRAM
// =============================================================================
class AxiTileDmaWithRam(
    val config: AxiTileDmaConfig = AxiTileDmaConfig(),
    val ramClockDomain: ClockDomain = null
) extends Component {

  val ramClock = if (ramClockDomain != null) ramClockDomain else ClockDomain.external("ram", withReset = true)

  val io = new Bundle {
    val s_apb = slave(Apb3(config.getApbConfig))
    val m_axi = master(Axi4WriteOnly(config.getAxi4Config))
    val irq = out Bool ()
    val irq_done = out Bool ()
    val irq_error = out Bool ()
    val irq_frame_done = out Bool ()

    // Per-thread External Write Ports into quad Tiled RAMs (Operate in high-frequency ramClock domain)
    val ram_wr_en = in Vec (Bool(), config.quadThreads)
    val ram_wr_addr = in Vec (UInt(config.threadWordAddrWidth bits), config.quadThreads)
    val ram_wr_data = in Vec (Bits(config.threadDataWidth bits), config.quadThreads)
  }

  noIoPrefix()

  def renameAxiForVivado(bundle: Bundle, prefix: String): Unit = {
    bundle.flatten.foreach { signal =>
      val name = signal.getName()
      val cleanName = name
        .replaceFirst("^io_", "")
        .replace(s"${prefix}_", "")
        .replace("_payload_", "")
        .replace("_payload", "")
        .replace("_", "")

      signal.setName(s"${prefix}_${cleanName}")
    }
  }

  renameAxiForVivado(io.m_axi, "m_axi")

  clockDomain.clock.setName("aclk")
  clockDomain.reset.setName("aresetn")

  val dma = new AxiTileDma(config, ramClockDomain = ramClock)
  dma.io.s_apb <> io.s_apb
  dma.io.m_axi <> io.m_axi
  io.irq := dma.io.irq
  io.irq_done := dma.io.irq_done
  io.irq_error := dma.io.irq_error
  io.irq_frame_done := dma.io.irq_frame_done

  // One Dual-Port BRAM per quad thread in high-frequency ramClock domain
  val ramArea = new ClockingArea(ramClock) {
    val tiledRams = for (t <- 0 until config.quadThreads) yield {
      val tiledRam = Mem(Bits(config.threadDataWidth bits), wordCount = config.threadTotalBeats)

      // One write port: the DMA's own writes (the write-back's clear, CLEAR) take it over the external
      // one, which only writes while the DMA is idle
      val dmaPort = dma.io.tile_ram(t)
      tiledRam.write(
        enable = io.ram_wr_en(t) || dmaPort.wr_en,
        address = dmaPort.wr_en ? (dmaPort.wr_addr >> config.threadBeatShift).resized | io.ram_wr_addr(t),
        data = dmaPort.wr_en ? dmaPort.wr_data | io.ram_wr_data(t)
      )

      // Convert byte-address back to word address for SpinalHDL simulation Mem
      val memRead = tiledRam.readSync(
        enable = dma.io.tile_ram(t).en,
        address = (dma.io.tile_ram(t).addr >> config.threadBeatShift).resized
      )
      dma.io.tile_ram(t).dout := Delay(memRead, cycleCount = config.bramReadLatency - 1)
      tiledRam
    }
  }
}

// =============================================================================
// Verilog Generation Entry Point
// =============================================================================
object AxiTileDmaVerilog {
  def main(args: Array[String]): Unit = {
    val config = AxiTileDmaConfig(
      addressWidth = 32,
      pixelsPerClock = 4, // 4 pixels per clock = 128-bit AXI data bus (configurable: 1, 2, 4, 8, 16)
      tileWidth = 128, // 128x128 tile known at compile time
      tileHeight = 128,
      maxBurstLength = 256,
      maxOutstanding = 8,
      idWidth = 4,
      cdcDepth = 32, // 32-entry async CDC, a LUTRAM's depth
      bramReadLatency = 4
    )

    SpinalConfig(
      targetDirectory = "rtl/AxiTileDma",
      defaultConfigForClockDomains = ClockDomainConfig(resetActiveLevel = LOW)
    ).withPrivateNamespace.generateVerilog(
      new AxiTileDma(
        config = config,
        ramClockDomain = ClockDomain.external("ram", withReset = true)
      )
    )
  }
}
