package lviv_gpu_modules

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba4.axi._
import spinal.lib.bus.amba3.apb._
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._
import spinal.lib.fsm._

// =============================================================================
// Configuration for AxiVisibilityDma
// =============================================================================
case class AxiVisibilityDmaConfig(
    addressWidth: Int = 32, // Address width (32 up to 64 bits)
    axiDataWidth: Int = 128, // AXI4 Read Master data width (>= 64 bits, e.g. 64, 128, 256)
    bttWidth: Int = 23, // DataMover BTT (Bytes To Transfer) width (up to 23 bits)
    gridWidth: Int = 10, // Visibility grid width in tiles (default: 10)
    gridHeight: Int = 6, // Visibility grid height in tiles (default: 6)
    vbWordBits: Int = 64, // Visibility buffer word width (64 bits: 60 bits grid + 4 bits padding)
    triangleSizeBytes: Int = 96, // Triangle data footprint in bytes (96 B: odd triangles start 32 B into a 64 B beat)
    maxBurstLength: Int = 256, // Max AXI4 Read burst beats (1..256)
    maxOutstandingReads: Int = 8, // Max outstanding AXI4 Read address transactions
    cmdFifoDepth: Int = 64, // Depth of DataMover command FIFO (64 entries reduces backpressure)
    stsFifoDepth: Int = 4, // Depth of DataMover status FIFO (4 entries since consumed 1 per clock)
    vbFifoDepth: Int = 256, // Depth of visibility read decoupling FIFO (512 entries fits in BRAM)
    useAutoAdvance: Boolean = true, // Support automatic tile index advancing (0..59)
    trianglesPerCycle: Int = 2 // Process 2 triangles per clock cycle (600 MTris/s @ 300MHz)
) {
  val gridTiles: Int = gridWidth * gridHeight
  require(gridTiles <= vbWordBits, s"gridTiles ($gridTiles) cannot exceed vbWordBits ($vbWordBits)")
  require(axiDataWidth >= vbWordBits, s"axiDataWidth ($axiDataWidth) must be >= vbWordBits ($vbWordBits)")
  require(isPow2(axiDataWidth), "axiDataWidth must be a power of 2 (e.g. 64, 128, 256)")
  require(
    axiDataWidth % vbWordBits == 0,
    s"axiDataWidth ($axiDataWidth) must be a multiple of vbWordBits ($vbWordBits)"
  )
  require(addressWidth >= 32 && addressWidth <= 64, "addressWidth must be between 32 and 64 bits")
  require(triangleSizeBytes > 0 && triangleSizeBytes % 32 == 0, "triangleSizeBytes must be a multiple of 32")
  require(maxBurstLength >= 1 && maxBurstLength <= 256, "maxBurstLength must be between 1 and 256 beats")
  require(cmdFifoDepth >= 4 && isPow2(cmdFifoDepth), "cmdFifoDepth must be a power of 2 >= 4")
  require(stsFifoDepth >= 4 && isPow2(stsFifoDepth), "stsFifoDepth must be a power of 2 >= 4")
  require(vbFifoDepth >= 4 && isPow2(vbFifoDepth), "vbFifoDepth must be a power of 2 >= 4")
  require(
    vbFifoDepth >= maxBurstLength,
    s"vbFifoDepth ($vbFifoDepth) must be >= maxBurstLength ($maxBurstLength) to guarantee full burst absorption"
  )
  require(
    bttWidth >= 8 && bttWidth <= 23,
    s"bttWidth ($bttWidth) must be between 8 and 23 bits (Xilinx DataMover limit)"
  )

  val wordsPerBeat: Int = axiDataWidth / vbWordBits

  // Triangle sizes are multiples of 32 B, so triangle addresses are carried in 32 B units
  val triAlignBytes: Int = 32
  val triAlignShift: Int = 5
  val triUnits: Int = triangleSizeBytes / triAlignBytes // Triangle size in 32 B units (3 for 96 B)
  val triWordAddrWidth: Int = addressWidth - triAlignShift // Address truncated by triAlignShift bits
  val axiBytesPerBeat: Int = axiDataWidth / 8 // 16 bytes for 128-bit
  val axiBeatShift: Int = log2Up(axiBytesPerBeat) // 4 bits for 16 bytes
  val vbBytesPerBeat: Int = axiBytesPerBeat
  val vbBeatShift: Int = axiBeatShift
  val vbWordAddrWidth: Int = addressWidth - axiBeatShift // Address truncated by axiBeatShift bits

  // Maximum triangles in a single BTT transfer: count * triangleSizeBytes must fit in bttWidth bits
  val maxBttTriangles: BigInt = ((BigInt(1) << bttWidth) - 1) / triangleSizeBytes // 87381 for 96 B @ 23 bits
  val bttTriCountWidth: Int = log2Up(maxBttTriangles + 1) // 17 bits for 96 B @ 23 bits

  // AMD / Xilinx LogiCORE IP AXI DataMover (PG022) Command Width
  // 72 bits for 32-bit address, 104 bits for 64-bit address
  val cmdWidth: Int = if (addressWidth <= 32) 72 else 104
  val stsWidth: Int = 8

  def getAxi4ReadConfig: Axi4Config = Axi4Config(
    addressWidth = addressWidth,
    dataWidth = axiDataWidth,
    idWidth = 4,
    useBurst = true,
    useSize = true,
    useLen = true,
    useLast = true,
    useResp = true,
    useId = true
  )

  def getApbConfig: Apb3Config = Apb3Config(
    addressWidth = 7,
    dataWidth = 32
  )
}

// =============================================================================
// Internal Compact Command Representation for DataMover FIFO
// =============================================================================
case class DataMoverCmdCompact(triWordAddrWidth: Int, bttTriCountWidth: Int) extends Bundle {
  val triWordAddr = UInt(triWordAddrWidth bits) // Truncated triangle address (byte address >> alignment shift)
  val triCount = UInt(bttTriCountWidth bits) // Triangle count (BTT = triCount * triangle size)
  val tag = Bits(4 bits)
}

// =============================================================================
// Visibility DMA Command Engine
// =============================================================================
class AxiVisibilityDma(
    val config: AxiVisibilityDmaConfig = AxiVisibilityDmaConfig(),
    val dmClockDomain: ClockDomain = null
) extends Component {

  // DataMover Clock Domain (if null, operates synchronously in default clockDomain)
  val dmClock = if (dmClockDomain != null) dmClockDomain else ClockDomain.current
  val isDualClock = (dmClockDomain != null) && (dmClockDomain != ClockDomain.current)

  val io = new Bundle {
    // 1. APB3 Slave Interface for Register Programming (aclk domain)
    val s_apb = slave(Apb3(config.getApbConfig))

    // 2. AXI4 Read Master Interface for Visibility Buffer (aclk domain)
    val m_axi_vb = master(Axi4ReadOnly(config.getAxi4ReadConfig))

    // 3. AXI-Stream Master for DataMover Commands (dmClock domain)
    val m_axis_datamover_cmd = master(Stream(Bits(config.cmdWidth bits)))

    // 4. AXI-Stream Slave for DataMover Status (dmClock domain)
    val s_axis_datamover_sts = slave(Stream(Bits(config.stsWidth bits)))

    // 5. Discrete Engine Status Outputs (aclk domain)
    val ready = out Bool () // Asserted when engine is IDLE and ready for a new START trigger
    val irq = out Bool () // Combined Interrupt output (masked)
    val irq_done = out Bool () // Dedicated Tile Done Interrupt output (masked)
    val irq_error = out Bool () // Dedicated Error Interrupt output (masked)
    val irq_frame_done = out Bool () // Dedicated Frame Done Interrupt output (masked)
  }

  noIoPrefix()

  // Vivado standard AXI4 memory-mapped bus port naming helper
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

  // Vivado standard AXI4-Stream port naming and interface attribute helper
  def renameAxisForVivado[T <: Data](stream: Stream[T], prefix: String): Unit = {
    stream.valid.setName(s"${prefix}_tvalid")
    stream.ready.setName(s"${prefix}_tready")
    stream.payload.setName(s"${prefix}_tdata")

    stream.valid.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:axis:1.0 ${prefix} TVALID")
    stream.ready.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:axis:1.0 ${prefix} TREADY")
    stream.payload.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:axis:1.0 ${prefix} TDATA")
  }

  renameAxiForVivado(io.m_axi_vb, "m_axi_vb")
  renameAxisForVivado(io.m_axis_datamover_cmd, "m_axis_datamover_cmd")
  renameAxisForVivado(io.s_axis_datamover_sts, "s_axis_datamover_sts")

  // AXI4 memory-mapped interface Vivado attributes
  io.m_axi_vb.flatten.foreach { sig =>
    val name = sig.getName()
    val suffix = name.replace("m_axi_vb_", "").toUpperCase
    sig.addAttribute("X_INTERFACE_INFO", s"xilinx.com:interface:aximm:1.0 m_axi_vb $suffix")
  }
  io.m_axi_vb.ar.valid.addAttribute(
    "X_INTERFACE_PARAMETER",
    s"NUM_READ_OUTSTANDING ${config.maxOutstandingReads}, READ_WRITE_MODE READ_ONLY"
  )

  // Vivado Interrupt Interface Attributes
  io.irq.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq INTERRUPT")
  io.irq.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_done.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_done INTERRUPT")
  io.irq_done.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_error.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_error INTERRUPT")
  io.irq_error.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")
  io.irq_frame_done.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:interrupt:1.0 irq_frame_done INTERRUPT")
  io.irq_frame_done.addAttribute("X_INTERFACE_PARAMETER", "SENSITIVITY LEVEL_HIGH")

  // Clock & Reset IP packaging attributes with ASSOCIATED_BUSIF
  clockDomain.clock.setName("aclk")
  clockDomain.reset.setName("aresetn")
  clockDomain.clock.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:clock:1.0 aclk CLK")
  clockDomain.clock.addAttribute(
    "X_INTERFACE_PARAMETER",
    if (isDualClock) {
      "ASSOCIATED_BUSIF m_axi_vb, ASSOCIATED_RESET aresetn"
    } else {
      "ASSOCIATED_BUSIF m_axi_vb:m_axis_datamover_cmd:s_axis_datamover_sts, ASSOCIATED_RESET aresetn"
    }
  )
  clockDomain.reset.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:reset:1.0 aresetn RST")
  clockDomain.reset.addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")

  if (isDualClock) {
    dmClock.clock.setName("dm_clk")
    dmClock.reset.setName("dm_resetn")
    dmClock.clock.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:clock:1.0 dm_clk CLK")
    dmClock.clock.addAttribute(
      "X_INTERFACE_PARAMETER",
      "ASSOCIATED_BUSIF m_axis_datamover_cmd:s_axis_datamover_sts, ASSOCIATED_RESET dm_resetn"
    )
    dmClock.reset.addAttribute("X_INTERFACE_INFO", "xilinx.com:signal:reset:1.0 dm_resetn RST")
    dmClock.reset.addAttribute("X_INTERFACE_PARAMETER", "POLARITY ACTIVE_LOW")
  }

  // ===========================================================================
  // 1. APB3 REGISTER INTERFACE (via SpinalHDL regif)
  // ===========================================================================
  val busif = Apb3BusInterface(io.s_apb, (0x0000, 128), "AXI_VISIBILITY_DMA")

  // Internal hardware status signals
  val dmaBusy = RegInit(False)
  val axiReadError = RegInit(False)
  val dmErrorFlag = RegInit(False)
  val dmLastStsReg = Reg(Bits(8 bits)) init (0)
  val cycleCounter = Reg(UInt(32 bits)) init (0)
  val statVisCount = Reg(UInt(32 bits)) init (0)
  val statCmdCount = Reg(UInt(32 bits)) init (0)
  val statStsCount = Reg(UInt(32 bits)) init (0)

  // 0x00: CONTROL REGISTER
  val REG_CTRL = busif.newRegAt(address = 0x00, doc = "DMA Control Register")
  val START = REG_CTRL.field(Bool(), W1P, doc = "Trigger visibility scan and command generation")
  val SOFT_RESET = REG_CTRL.field(Bool(), W1P, doc = "Software reset for engine and internal FIFOs")
  val IRQ_ENABLE = REG_CTRL.field(Bool(), RW, resetValue = 1, doc = "Global Interrupt Enable (1: enabled)")
  val AUTO_ADV_EN =
    if (config.useAutoAdvance) REG_CTRL.field(Bool(), RW, resetValue = 1, doc = "Enable auto-advancing tile index")
    else null

  // 0x04: STATUS REGISTER (W1C fields are internal registers in regif)
  val REG_STATUS = busif.newRegAt(address = 0x04, doc = "DMA Status Register")
  val BUSY = REG_STATUS.field(Bool(), RO, doc = "Engine active busy status")
  val DONE = REG_STATUS.field(Bool(), W1C, doc = "Tile processing complete (Write 1 to clear)")
  val ERROR = REG_STATUS.field(Bool(), W1C, doc = "Error detected on AXI read or DataMover (Write 1 to clear)")
  val IRQ_STATUS = REG_STATUS.field(Bool(), W1C, doc = "Interrupt pending (Write 1 to clear)")
  val FRAME_DONE =
    if (config.useAutoAdvance)
      REG_STATUS.field(Bool(), W1C, doc = "All 60 tiles completed / wrapped (Write 1 to clear)")
    else null
  val AXI_ERR_FLAG = REG_STATUS.field(Bool(), RO, doc = "AXI Read Master Bus Error")
  val DM_ERR_FLAG = REG_STATUS.field(Bool(), RO, doc = "DataMover Status Error")

  BUSY := dmaBusy
  AXI_ERR_FLAG := axiReadError
  DM_ERR_FLAG := dmErrorFlag

  // 0x08: VB_BASE_ADDR_LOW (8-byte aligned, bits [2:0] reserved/ignored)
  val REG_VB_LOW = busif.newRegAt(address = 0x08, doc = "Visibility Buffer Base Address [31:0] (8-byte aligned)")
  REG_VB_LOW.reserved(config.vbBeatShift bits)
  val VB_BASE_LOW = REG_VB_LOW.field(
    UInt((32 - config.vbBeatShift) bits),
    RW,
    resetValue = 0,
    doc = "Visibility Buffer Base Address [31:3]"
  )

  // 0x0C: VB_BASE_ADDR_HIGH
  val REG_VB_HIGH = busif.newRegAt(address = 0x0c, doc = "Visibility Buffer Base Address [63:32]")
  val VB_BASE_HIGH =
    REG_VB_HIGH.field(UInt(32 bits), RW, resetValue = 0, doc = "Upper 32 bits of Visibility Buffer Base Address")

  // 0x10: TRI_BASE_ADDR_LOW (triAlignBytes aligned, bits [triAlignShift-1:0] reserved/ignored)
  val REG_TRI_LOW = busif.newRegAt(
    address = 0x10,
    doc = s"Triangle Geometry Base Address [31:0] (${config.triAlignBytes}-byte aligned)"
  )
  REG_TRI_LOW.reserved(config.triAlignShift bits)
  val TRI_BASE_LOW = REG_TRI_LOW.field(
    UInt((32 - config.triAlignShift) bits),
    RW,
    resetValue = 0,
    doc = s"Triangle Geometry Base Address [31:${config.triAlignShift}]"
  )

  // 0x14: TRI_BASE_ADDR_HIGH
  val REG_TRI_HIGH = busif.newRegAt(address = 0x14, doc = "Triangle Geometry Base Address [63:32]")
  val TRI_BASE_HIGH =
    REG_TRI_HIGH.field(UInt(32 bits), RW, resetValue = 0, doc = "Upper 32 bits of Triangle Geometry Base Address")

  // 0x18: TRI_COUNT (N)
  val REG_TRI_COUNT = busif.newRegAt(address = 0x18, doc = "Triangle Count (N elements)")
  val TRI_COUNT = REG_TRI_COUNT.field(
    UInt(32 bits),
    RW,
    resetValue = 0,
    doc = "Total number of triangle visibility elements to evaluate"
  )

  // 0x1C: TILE_INDEX
  val REG_TILE_IDX = busif.newRegAt(address = 0x1c, doc = "Active Tile Index (0..59)")
  val TILE_INDEX = REG_TILE_IDX.field(
    UInt(log2Up(config.gridTiles) bits),
    RW,
    resetValue = 0,
    doc = "Tile selection bit index (0..59) in 64-bit visibility word"
  )

  // 0x20: BTT_LIMIT (triangle count; BTT bytes = count * triangleSizeBytes)
  val REG_BTT_LIMIT = busif.newRegAt(address = 0x20, doc = "Max Triangles per DataMover Command")
  val BTT_LIMIT_TRI = REG_BTT_LIMIT.field(
    UInt(config.bttTriCountWidth bits),
    RW,
    resetValue = config.maxBttTriangles,
    doc = s"Max triangles per command (BTT = count * ${config.triangleSizeBytes} B; 0 = ${config.maxBttTriangles})"
  )

  // 0x24: STAT_VIS_COUNT
  val REG_STAT_VIS = busif.newRegAt(address = 0x24, doc = "Visible Triangle Counter")
  val STAT_VIS = REG_STAT_VIS.field(UInt(32 bits), RO, doc = "Total visible triangles encountered in current tile")
  STAT_VIS := statVisCount

  // 0x28: STAT_CMD_COUNT
  val REG_STAT_CMD = busif.newRegAt(address = 0x28, doc = "DataMover Commands Issued Counter")
  val STAT_CMD = REG_STAT_CMD.field(UInt(32 bits), RO, doc = "Total DataMover command packets sent")
  STAT_CMD := statCmdCount

  // 0x2C: STAT_STS_COUNT
  val REG_STAT_STS = busif.newRegAt(address = 0x2c, doc = "DataMover Status Received Counter")
  val STAT_STS = REG_STAT_STS.field(UInt(32 bits), RO, doc = "Total DataMover status responses received")
  STAT_STS := statStsCount

  // 0x30: DM_LAST_STS
  val REG_DM_LAST = busif.newRegAt(address = 0x30, doc = "Last DataMover Status Byte")
  val DM_LAST_STS = REG_DM_LAST.field(Bits(8 bits), RO, doc = "Last received raw status byte from DataMover")
  DM_LAST_STS := dmLastStsReg

  // 0x34: PERF_CYCLES
  val REG_PERF = busif.newRegAt(address = 0x34, doc = "Performance Cycle Counter")
  val PERF_CYCLES = REG_PERF.field(UInt(32 bits), RO, doc = "Elapsed clock cycles during active tile scan")
  PERF_CYCLES := cycleCounter

  // ===========================================================================
  // INTERRUPT FACTORY REGISTERS (0x40 - 0x4C)
  // RegGroup RFMS4:
  //   0x40: INTR_INT_RAW    - Raw interrupt event flags (W1C: write 1 to clear)
  //   0x44: INTR_INT_FORCE  - Software debug force (W1S: write 1 to trigger raw)
  //   0x48: INTR_INT_MASK   - Mask register (RW: 1 = masked/off, 0 = unmasked/open)
  //   0x4C: INTR_INT_STATUS - Masked status register (RO: raw && !mask)
  // Fields:
  //   Bit 0: done           - Tile scan & command generation complete
  //   Bit 1: error          - AXI read error or DataMover status error
  //   Bit 2: frame_done     - All 60 tiles completed (Auto-Advance wrap)
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

  // Built-in Documentation & C Header Generators
  busif.accept(HtmlGenerator("axi_visibility_dma_regmap", "AXI_VISIBILITY_DMA"))
  busif.accept(CHeaderGenerator("axi_visibility_dma_regmap", "AXI_VISIBILITY_DMA"))
  busif.accept(JsonGenerator("axi_visibility_dma_regmap"))

  // Full base addresses truncated by alignment (zeros implicitly appended)
  val fullVbWordAddr = UInt(config.vbWordAddrWidth bits)
  if (config.addressWidth > 32) {
    fullVbWordAddr := (VB_BASE_HIGH @@ VB_BASE_LOW).resized
  } else {
    fullVbWordAddr := VB_BASE_LOW.resized
  }
  val fullVbBaseAddr = fullVbWordAddr @@ U(0, config.vbBeatShift bits)

  val fullTriWordAddr = UInt(config.triWordAddrWidth bits)
  if (config.addressWidth > 32) {
    fullTriWordAddr := (TRI_BASE_HIGH @@ TRI_BASE_LOW).resized
  } else {
    fullTriWordAddr := TRI_BASE_LOW.resized
  }

  // Discrete status & interrupt outputs
  val rawBits = INTR.RAW.readBits
  io.ready := !dmaBusy
  io.irq := irqMerged
  io.irq_done := rawBits(0)
  io.irq_error := rawBits(1)
  io.irq_frame_done := (if (config.useAutoAdvance) rawBits(2) else False)

  when(IRQ_ENABLE && (intrDone || intrError || intrFrameDone)) {
    IRQ_STATUS := True
  }

  when(dmaBusy) {
    cycleCounter := cycleCounter + 1
  }

  // Active tile index (latched upon START and held constant across entire triangle stream)
  val activeTileIdx = Reg(UInt(log2Up(config.gridTiles) bits)) init (0)

  // ===========================================================================
  // 2. AXI READ BOUNDARY BUFFER & VISIBILITY FILTER (aclk domain)
  // Step 1: Buffer the entire incoming AXI beat (128/512 bits) in an input register slice (m2sPipe).
  //         Captures all bits at the physical boundary into flip-flops, breaking timing paths.
  // Step 2: Feed buffered data into the 64:1 multiplexer to extract 1 bit per triangle.
  // Step 3: Push only the 1-bit per triangle (wordsPerBeat bits) into vbFifo.
  // ===========================================================================
  val rBuffered = io.m_axi_vb.r.m2sPipe()

  val visBitsIn = Bits(config.wordsPerBeat bits)
  for (k <- 0 until config.wordsPerBeat) {
    visBitsIn(k) := rBuffered.payload.data(k * config.vbWordBits + activeTileIdx)
  }

  val vbFifo = StreamFifo(
    dataType = Bits(config.wordsPerBeat bits),
    depth = config.vbFifoDepth
  )

  vbFifo.io.push.valid := rBuffered.valid
  vbFifo.io.push.payload := visBitsIn
  rBuffered.ready := vbFifo.io.push.ready

  // ===========================================================================
  // 3. AXI4 READ MASTER ENGINE (aclk domain)
  // Splits N 64-bit element reads into bursts, respecting 4KB DRAM boundaries
  // ===========================================================================
  val arAddrReg = Reg(UInt(config.addressWidth bits)) init (0)
  val arBeatsRemaining = Reg(UInt(32 bits)) init (0)
  val rBeatsRemaining = Reg(UInt(32 bits)) init (0)
  val outstandingReads = Reg(UInt(log2Up(config.maxOutstandingReads + 1) bits)) init (0)

  // 4KB boundary calculation for visibility buffer reads: address bits [11:0] cannot cross 4096 bytes
  val bytesTo4KbBoundary = U(4096, 13 bits) - arAddrReg(11 downto 0).resize(13)
  val beatsTo4KbBoundary = (bytesTo4KbBoundary >> config.vbBeatShift).resize(16)
  val maxBurstBeats = U(config.maxBurstLength, 16 bits)

  val currentBurstLen = UInt(16 bits)
  currentBurstLen := arBeatsRemaining.min(beatsTo4KbBoundary.resized).min(maxBurstBeats.resized).resized

  val canIssueAr = (arBeatsRemaining > 0) && (outstandingReads < config.maxOutstandingReads)
  io.m_axi_vb.ar.valid := canIssueAr && dmaBusy
  io.m_axi_vb.ar.addr := arAddrReg
  io.m_axi_vb.ar.len := (currentBurstLen - 1).resized
  io.m_axi_vb.ar.size := U(config.vbBeatShift, 3 bits)
  io.m_axi_vb.ar.burst := Axi4.burst.INCR
  io.m_axi_vb.ar.id := 0
  if (config.getAxi4ReadConfig.useRegion) io.m_axi_vb.ar.region.clearAll()
  if (config.getAxi4ReadConfig.useLock) io.m_axi_vb.ar.lock.clearAll()
  if (config.getAxi4ReadConfig.useCache) io.m_axi_vb.ar.cache := B"0011"
  if (config.getAxi4ReadConfig.useProt) io.m_axi_vb.ar.prot.clearAll()
  if (config.getAxi4ReadConfig.useQos) io.m_axi_vb.ar.qos.clearAll()

  val arFire = io.m_axi_vb.ar.fire
  val rFire = io.m_axi_vb.r.fire
  val rLast = io.m_axi_vb.r.last

  when(arFire) {
    val burstBytes = currentBurstLen << config.vbBeatShift
    arAddrReg := arAddrReg + burstBytes.resized
    arBeatsRemaining := arBeatsRemaining - currentBurstLen.resized
  }

  when(arFire && !(rFire && rLast)) {
    outstandingReads := outstandingReads + 1
  }.elsewhen(!arFire && (rFire && rLast)) {
    outstandingReads := outstandingReads - 1
  }

  when(rFire) {
    rBeatsRemaining := rBeatsRemaining - 1
    when(io.m_axi_vb.r.resp === Axi4.resp.SLVERR || io.m_axi_vb.r.resp === Axi4.resp.DECERR) {
      axiReadError := True
      ERROR := True
      intrError := True
    }
  }

  // ===========================================================================
  // 4. COMPACT COMMAND STREAM & CONFIGURABLE CLOCK FIFO
  // Stores only (triWordAddr, triCount, tag) in the FIFO.
  // ===========================================================================
  val cmdStreamInternal = Stream(DataMoverCmdCompact(config.triWordAddrWidth, config.bttTriCountWidth))

  val cmdStreamOut = if (isDualClock) {
    val cc = StreamFifoCC(
      dataType = DataMoverCmdCompact(config.triWordAddrWidth, config.bttTriCountWidth),
      depth = config.cmdFifoDepth,
      pushClock = clockDomain,
      popClock = dmClock
    )
    cc.io.push <> cmdStreamInternal
    cc.io.pop
  } else {
    val sync = StreamFifo(
      dataType = DataMoverCmdCompact(config.triWordAddrWidth, config.bttTriCountWidth),
      depth = config.cmdFifoDepth
    )
    sync.io.push <> cmdStreamInternal
    sync.io.pop
  }

  // Constant multiply via shift-and-add (keeps small constants like 3 out of DSPs)
  def mulConst(x: UInt, c: Int): UInt = {
    val width = x.getWidth + log2Up(c + 1)
    (0 until log2Up(c + 1))
      .filter(b => ((c >> b) & 1) == 1)
      .map(b => (x.resize(width) << b).resize(width))
      .reduce(_ + _)
  }

  // Format AMD/Xilinx DataMover MM2S command packet at output port (dmClock domain)
  val dmArea = new ClockingArea(dmClock) {
    val cmdPayload = Bits(config.cmdWidth bits)
    cmdPayload := 0

    // Reconstruct full BTT bytes: (triCount * triUnits) << triAlignShift = triCount * triangleSizeBytes
    val bttUnits = mulConst(cmdStreamOut.payload.triCount, config.triUnits)
    val bttBytes = (bttUnits @@ U(0, config.triAlignShift bits)).resize(config.bttWidth)
    cmdPayload(config.bttWidth - 1 downto 0) := bttBytes.asBits

    // [23] Type: 1 = INCR burst
    cmdPayload(23) := True
    // [27:24] DSA: Stream alignment offset
    cmdPayload(27 downto 24) := 0
    // [28] EOF: Not used (tied False)
    cmdPayload(28) := False
    // [29] DRR: Data Realignment Engine disabled. SADDR is the exact triangle address; with 96 B
    // triangles, runs starting on an odd triangle begin 32 B into a 64 B beat (consumer realigns)
    cmdPayload(29) := False
    // [31:30] TAG: echo tag
    cmdPayload(31 downto 30) := cmdStreamOut.payload.tag(1 downto 0)

    // Reconstruct full byte address: (triWordAddr << triAlignShift)
    val startByteAddr = cmdStreamOut.payload.triWordAddr @@ U(0, config.triAlignShift bits)
    if (config.addressWidth <= 32) {
      // [63:32] SADDR: 32-bit Starting Address
      cmdPayload(63 downto 32) := startByteAddr.resize(32).asBits
    } else {
      // [32+addrWidth-1 : 32] SADDR: 64-bit Starting Address
      cmdPayload(32 + config.addressWidth - 1 downto 32) := startByteAddr.asBits
    }

    io.m_axis_datamover_cmd.valid := cmdStreamOut.valid
    io.m_axis_datamover_cmd.payload := cmdPayload
    cmdStreamOut.ready := io.m_axis_datamover_cmd.ready
  }

  // ===========================================================================
  // 5. STATUS STREAM & IN-FLIGHT RETIREMENT TRACKER
  // Crosses status beats back from dmClock to aclk and checks for errors.
  // ===========================================================================
  val stsStreamInternal = if (isDualClock) {
    val ccSts = StreamFifoCC(
      dataType = Bits(config.stsWidth bits),
      depth = config.stsFifoDepth,
      pushClock = dmClock,
      popClock = clockDomain
    )
    ccSts.io.push <> io.s_axis_datamover_sts
    ccSts.io.pop
  } else {
    val syncSts = StreamFifo(
      dataType = Bits(config.stsWidth bits),
      depth = config.stsFifoDepth
    )
    syncSts.io.push <> io.s_axis_datamover_sts
    syncSts.io.pop
  }

  // Always accept status beats to prevent deadlocking downstream DataMover
  stsStreamInternal.ready := True

  when(stsStreamInternal.fire) {
    val stsByte = stsStreamInternal.payload(7 downto 0)
    dmLastStsReg := stsByte
    statStsCount := statStsCount + 1

    // Xilinx DataMover MM2S Status decoding:
    // sts[7] = OKAY (1 = transfer completed successfully)
    // sts[6] = SLVERR
    // sts[5] = DECERR
    // sts[4] = INTERR
    val isOkay = stsByte(7)
    val hasError = !isOkay || stsByte(6 downto 4) =/= 0
    when(hasError) {
      dmErrorFlag := True
      ERROR := True
      intrError := True
    }
  }

  // ===========================================================================
  // 6. VISIBILITY FILTER & UNCHUNKED BTT AGGREGATOR (aclk domain)
  // Continually aggregates contiguous visible triangles; only limited by BTT!
  // ===========================================================================
  // Note: activeTileIdx declared above vbFifo
  val triCounter = Reg(UInt(32 bits)) init (0)
  val shadowTriCount = Reg(UInt(32 bits)) init (0)
  // Running addresses (triAlignBytes units) of triIdx0 / triIdx1, advanced together with triCounter.
  // Replaces base + idx * triangleSizeBytes: no multiplier or base adder in the filter loop.
  val triAddr0 = Reg(UInt(config.triWordAddrWidth bits)) init (0)
  val triAddr1 = Reg(UInt(config.triWordAddrWidth bits)) init (0)
  val shadowMaxTriangles = Reg(UInt(config.bttTriCountWidth bits)) init (config.maxBttTriangles)
  val tagCounter = Reg(UInt(4 bits)) init (0)

  // Aggregation state variables
  val runActive = RegInit(False)
  val runStartWord = Reg(UInt(config.triWordAddrWidth bits)) init (0)
  val runLength = Reg(UInt(config.bttTriCountWidth bits)) init (0)

  // 1-bit visibility signals for 2 triangles per cycle
  val isParallel2 = (config.trianglesPerCycle == 2) && (config.wordsPerBeat >= 2)

  val triIdx0 = triCounter
  val triIdx1 = triCounter + 1
  val isValid0 = (triIdx0 < shadowTriCount)
  val isValid1 = (triIdx1 < shadowTriCount)

  val rawV0 = vbFifo.io.pop.payload(0)
  val rawV1 = if (config.wordsPerBeat >= 2) vbFifo.io.pop.payload(1) else False

  // Mask v1 if beyond shadowTriCount (odd triangle count on last beat)
  val v0 = rawV0 && isValid0
  val v1 = rawV1 && isValid1

  val isLastBeat = (triCounter + 2 >= shadowTriCount)
  val isLastTri1 = (triIdx1 === (shadowTriCount - 1))
  val stepCount = Mux(isValid1, U(2, 32 bits), U(1, 32 bits))
  val stepUnits = Mux(
    isValid1,
    U(2 * config.triUnits, config.triWordAddrWidth bits),
    U(config.triUnits, config.triWordAddrWidth bits)
  )

  // Advance triangle index and running addresses by one beat (1 or 2 triangles)
  def advancePair(): Unit = {
    triCounter := triCounter + stepCount
    triAddr0 := triAddr0 + stepUnits
    triAddr1 := triAddr1 + stepUnits
  }

  // Advance triangle index and running addresses by one triangle (serial mode)
  def advanceOne(): Unit = {
    triCounter := triCounter + 1
    triAddr0 := triAddr0 + config.triUnits
    triAddr1 := triAddr1 + config.triUnits
  }

  // Sub-word slicer when trianglesPerCycle == 1 and wordsPerBeat > 1
  val sliceIdx = Reg(UInt(log2Up(config.wordsPerBeat max 2) bits)) init (0)

  // 1-bit visibility indicator for the single-triangle engine
  val isVisible = if (config.wordsPerBeat == 1) {
    vbFifo.io.pop.payload(0)
  } else {
    vbFifo.io.pop.payload(sliceIdx.resize(log2Up(config.wordsPerBeat)))
  }

  val isLastTri = (triCounter === (shadowTriCount - 1))
  val curTriWordAddr = triAddr0

  // Step pulse to advance to next triangle (used only when !isParallel2)
  val triStep = False

  // Default stream controls:
  vbFifo.io.pop.ready := False
  cmdStreamInternal.valid := False
  cmdStreamInternal.payload.triWordAddr := runStartWord
  cmdStreamInternal.payload.triCount := runLength
  cmdStreamInternal.payload.tag := tagCounter.asBits

  def pushCmd(addr: UInt, count: UInt): Unit = {
    cmdStreamInternal.valid := True
    cmdStreamInternal.payload.triWordAddr := addr
    cmdStreamInternal.payload.triCount := count
    cmdStreamInternal.payload.tag := tagCounter.asBits
  }

  object FilterState extends SpinalEnum {
    val IDLE, FILTER_STREAM, FLUSH_STALL, WAIT_RETIRE, ADVANCE_TILE = newElement()
  }
  val filterState = RegInit(FilterState.IDLE)

  when(SOFT_RESET) {
    filterState := FilterState.IDLE
    dmaBusy := False
    axiReadError := False
    dmErrorFlag := False
    statVisCount := 0
    statCmdCount := 0
    statStsCount := 0
    runActive := False
    runLength := 0
    outstandingReads := 0
    sliceIdx := 0
  }.otherwise {
    switch(filterState) {
      is(FilterState.IDLE) {
        when(START && !dmaBusy) {
          dmaBusy := True
          DONE := False
          ERROR := False
          IRQ_STATUS := False
          if (config.useAutoAdvance) FRAME_DONE := False
          axiReadError := False
          dmErrorFlag := False
          cycleCounter := 0
          statVisCount := 0
          statCmdCount := 0
          statStsCount := 0
          tagCounter := 0
          runActive := False
          runLength := 0
          sliceIdx := 0

          activeTileIdx := TILE_INDEX
          shadowTriCount := TRI_COUNT
          triAddr0 := fullTriWordAddr
          triAddr1 := fullTriWordAddr + config.triUnits

          // Sizing limitation is ONLY the BTT capacity
          shadowMaxTriangles := (BTT_LIMIT_TRI === 0) ? U(
            config.maxBttTriangles,
            config.bttTriCountWidth bits
          ) | BTT_LIMIT_TRI

          // Setup AXI4 Visibility Buffer Reader
          arAddrReg := fullVbBaseAddr
          val beatShift = log2Up(config.wordsPerBeat)
          val totalBeats = UInt(32 bits)
          if (config.wordsPerBeat == 1) {
            totalBeats := TRI_COUNT
          } else {
            totalBeats := ((TRI_COUNT + (config.wordsPerBeat - 1)) >> beatShift).resized
          }
          arBeatsRemaining := totalBeats
          rBeatsRemaining := totalBeats
          triCounter := 0

          when(TRI_COUNT === 0) {
            filterState := FilterState.ADVANCE_TILE
          }.otherwise {
            filterState := FilterState.FILTER_STREAM
          }
        }
      }

      is(FilterState.FILTER_STREAM) {
        when(vbFifo.io.pop.valid) {
          if (isParallel2) {
            switch(v0 ## v1) {
              // ---------------------------------------------------------------
              // Case 00: Both triangles invisible
              // ---------------------------------------------------------------
              is(B"00") {
                when(runActive) {
                  pushCmd(runStartWord, runLength)
                  when(cmdStreamInternal.ready) {
                    statCmdCount := statCmdCount + 1
                    tagCounter := tagCounter + 1
                    runActive := False
                    runLength := 0
                    vbFifo.io.pop.ready := True
                    advancePair()
                    when(isLastBeat) {
                      filterState := FilterState.WAIT_RETIRE
                    }
                  }
                }.otherwise {
                  vbFifo.io.pop.ready := True
                  advancePair()
                  when(isLastBeat) {
                    filterState := FilterState.WAIT_RETIRE
                  }
                }
              }

              // ---------------------------------------------------------------
              // Case 01: v0 invisible, v1 visible (starts new run at triIdx1)
              // Note: If N is odd, v1 is masked to False, so this case cannot occur
              // ---------------------------------------------------------------
              is(B"01") {
                when(runActive) {
                  pushCmd(runStartWord, runLength)
                  when(cmdStreamInternal.ready) {
                    statCmdCount := statCmdCount + 1
                    tagCounter := tagCounter + 1
                    when(isLastTri1) {
                      // v1 is also last: flush previous run, next cycle flushes v1
                      runActive := False
                      runLength := 0
                    }.otherwise {
                      runActive := True
                      runStartWord := triAddr1
                      runLength := 1
                      statVisCount := statVisCount + 1
                      vbFifo.io.pop.ready := True
                      advancePair()
                    }
                  }
                }.otherwise {
                  when(isLastTri1) {
                    pushCmd(triAddr1, 1)
                    when(cmdStreamInternal.ready) {
                      statCmdCount := statCmdCount + 1
                      tagCounter := tagCounter + 1
                      statVisCount := statVisCount + 1
                      vbFifo.io.pop.ready := True
                      advancePair()
                      filterState := FilterState.WAIT_RETIRE
                    }
                  }.otherwise {
                    runActive := True
                    runStartWord := triAddr1
                    runLength := 1
                    statVisCount := statVisCount + 1
                    vbFifo.io.pop.ready := True
                    advancePair()
                  }
                }
              }

              // ---------------------------------------------------------------
              // Case 10: v0 visible, v1 invisible (run ends at v0)
              // ---------------------------------------------------------------
              is(B"10") {
                when(runActive) {
                  val canExtend = (runLength < shadowMaxTriangles)
                  when(canExtend) {
                    val totalRun = (runLength + 1).resize(config.bttTriCountWidth)
                    pushCmd(runStartWord, totalRun)
                    when(cmdStreamInternal.ready) {
                      statCmdCount := statCmdCount + 1
                      tagCounter := tagCounter + 1
                      statVisCount := statVisCount + 1
                      runActive := False
                      runLength := 0
                      vbFifo.io.pop.ready := True
                      advancePair()
                      when(isLastBeat) {
                        filterState := FilterState.WAIT_RETIRE
                      }
                    }
                  }.otherwise {
                    pushCmd(runStartWord, runLength)
                    when(cmdStreamInternal.ready) {
                      statCmdCount := statCmdCount + 1
                      tagCounter := tagCounter + 1
                      runActive := False
                      runLength := 0
                    }
                  }
                }.otherwise {
                  pushCmd(triAddr0, 1)
                  when(cmdStreamInternal.ready) {
                    statCmdCount := statCmdCount + 1
                    tagCounter := tagCounter + 1
                    statVisCount := statVisCount + 1
                    vbFifo.io.pop.ready := True
                    advancePair()
                    when(isLastBeat) {
                      filterState := FilterState.WAIT_RETIRE
                    }
                  }
                }
              }

              // ---------------------------------------------------------------
              // Case 11: Both v0 and v1 visible!
              // ---------------------------------------------------------------
              is(B"11") {
                when(runActive) {
                  val canExtend2 = (runLength + 2 <= shadowMaxTriangles)

                  when(canExtend2) {
                    when(isLastTri1) {
                      val totalRun = (runLength + 2).resize(config.bttTriCountWidth)
                      pushCmd(runStartWord, totalRun)
                      when(cmdStreamInternal.ready) {
                        statCmdCount := statCmdCount + 1
                        tagCounter := tagCounter + 1
                        statVisCount := statVisCount + 2
                        runActive := False
                        runLength := 0
                        vbFifo.io.pop.ready := True
                        advancePair()
                        filterState := FilterState.WAIT_RETIRE
                      }
                    }.otherwise {
                      runLength := runLength + 2
                      statVisCount := statVisCount + 2
                      vbFifo.io.pop.ready := True
                      advancePair()
                    }
                  }.otherwise {
                    // Current run cannot fit 2 more triangles; flush current run first
                    pushCmd(runStartWord, runLength)
                    when(cmdStreamInternal.ready) {
                      statCmdCount := statCmdCount + 1
                      tagCounter := tagCounter + 1
                      runActive := False
                      runLength := 0
                    }
                  }
                }.otherwise {
                  when(isLastTri1) {
                    pushCmd(triAddr0, 2)
                    when(cmdStreamInternal.ready) {
                      statCmdCount := statCmdCount + 1
                      tagCounter := tagCounter + 1
                      statVisCount := statVisCount + 2
                      vbFifo.io.pop.ready := True
                      advancePair()
                      filterState := FilterState.WAIT_RETIRE
                    }
                  }.otherwise {
                    runActive := True
                    runStartWord := triAddr0
                    runLength := 2
                    statVisCount := statVisCount + 2
                    vbFifo.io.pop.ready := True
                    advancePair()
                  }
                }
              }
            }
          } else {
            // Serialized 1 triangle per clock cycle
            when(isVisible) {
              when(!runActive) {
                when(isLastTri) {
                  pushCmd(curTriWordAddr, 1)
                  when(cmdStreamInternal.ready) {
                    triStep := True
                    statCmdCount := statCmdCount + 1
                    tagCounter := tagCounter + 1
                    filterState := FilterState.WAIT_RETIRE
                  }
                }.otherwise {
                  runActive := True
                  runStartWord := curTriWordAddr
                  runLength := 1
                  triStep := True
                }
              }.otherwise {
                val canExtend = (runLength < shadowMaxTriangles)
                when(canExtend) {
                  when(isLastTri) {
                    val totalRunLen = (runLength + 1).resize(config.bttTriCountWidth)
                    pushCmd(runStartWord, totalRunLen)
                    when(cmdStreamInternal.ready) {
                      triStep := True
                      statCmdCount := statCmdCount + 1
                      tagCounter := tagCounter + 1
                      runActive := False
                      filterState := FilterState.WAIT_RETIRE
                    }
                  }.otherwise {
                    runLength := runLength + 1
                    triStep := True
                  }
                }.otherwise {
                  pushCmd(runStartWord, runLength)
                  when(cmdStreamInternal.ready) {
                    statCmdCount := statCmdCount + 1
                    tagCounter := tagCounter + 1
                    runActive := False
                    filterState := FilterState.FLUSH_STALL
                  }
                }
              }
            }.otherwise {
              when(runActive) {
                pushCmd(runStartWord, runLength)
                when(cmdStreamInternal.ready) {
                  triStep := True
                  statCmdCount := statCmdCount + 1
                  tagCounter := tagCounter + 1
                  runActive := False
                  when(isLastTri) {
                    filterState := FilterState.WAIT_RETIRE
                  }
                }
              }.otherwise {
                triStep := True
                when(isLastTri) {
                  filterState := FilterState.WAIT_RETIRE
                }
              }
            }
          }
        }
      }

      // Intermediate cycle after pushing a full block to cleanly start next run
      is(FilterState.FLUSH_STALL) {
        filterState := FilterState.FILTER_STREAM
      }

      // Wait until all issued DataMover commands have been acknowledged via status stream
      is(FilterState.WAIT_RETIRE) {
        when(statStsCount === statCmdCount) {
          filterState := FilterState.ADVANCE_TILE
        }
      }

      // Transfer complete: advance tile index and signal completion
      is(FilterState.ADVANCE_TILE) {
        dmaBusy := False
        DONE := True
        intrDone := True

        when(IRQ_ENABLE) {
          IRQ_STATUS := True
        }

        if (config.useAutoAdvance) {
          when(AUTO_ADV_EN) {
            when(TILE_INDEX === (config.gridTiles - 1)) {
              TILE_INDEX := 0
              FRAME_DONE := True
              intrFrameDone := True
            }.otherwise {
              TILE_INDEX := TILE_INDEX + 1
            }
          }
        }

        filterState := FilterState.IDLE
      }
    }

    // Triangle step & FIFO pop logic (only for 1-triangle-per-clock mode)
    if (!isParallel2) {
      if (config.wordsPerBeat == 1) {
        when(triStep) {
          vbFifo.io.pop.ready := True
          advanceOne()
          when(isVisible) {
            statVisCount := statVisCount + 1
          }
        }
      } else {
        when(triStep) {
          advanceOne()
          when(isVisible) {
            statVisCount := statVisCount + 1
          }
          when(sliceIdx === (config.wordsPerBeat - 1) || isLastTri) {
            vbFifo.io.pop.ready := True
            sliceIdx := 0
          }.otherwise {
            sliceIdx := sliceIdx + 1
          }
        }
      }
    }
  }
}

// =============================================================================
// Verilog RTL Generation Entry Point
// =============================================================================
object AxiVisibilityDmaVerilog {
  def main(args: Array[String]): Unit = {
    val config = AxiVisibilityDmaConfig(
      addressWidth = 32,
      axiDataWidth = 128, // 128-bit AXI Read Master (configurable >= 64 bits)
      bttWidth = 23, // Configurable up to 23 bits
      gridWidth = 10,
      gridHeight = 6,
      vbWordBits = 64,
      triangleSizeBytes = 96,
      maxBurstLength = 256,
      maxOutstandingReads = 8,
      cmdFifoDepth = 64,
      stsFifoDepth = 4,
      vbFifoDepth = 512, // >= maxBurstLength
      useAutoAdvance = true
    )

    SpinalConfig(
      targetDirectory = "rtl/AxiVisibilityDma",
      defaultConfigForClockDomains = ClockDomainConfig(resetActiveLevel = LOW)
    ).withPrivateNamespace.generateVerilog(
      new AxiVisibilityDma(
        config = config,
        dmClockDomain = null
      )
    )
  }
}
