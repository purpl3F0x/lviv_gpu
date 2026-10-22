# SpinalHDL modules of rtl/spinalhdl. Their Verilog goes to rtl/generated/ and their register maps
# to sdk/include/generated/<Name>/; neither is tracked.
#
# Include from a Makefile and list the Verilog it uses as $(SPINAL_GEN_DIR)/<Name>.v, so its rules
# can depend on it. A module is regenerated, by one sbt run of its own generator, when one of its
# outputs is missing or older than its Scala sources (SPINAL_SRCS_<Name>, plus the sbt build).
# `make spinal` brings every module up to date. Don't use make -j for this: two sbt runs on the
# same build at once fight over it.

SPINAL_MK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SPINAL_REPO_ROOT := $(abspath $(SPINAL_MK_DIR)/..)
SPINAL_DIR = $(SPINAL_REPO_ROOT)/rtl/spinalhdl
SPINAL_SRC_DIR = $(SPINAL_DIR)/hw/spinal/lviv_gpu_modules
# Where the generators write (their SpinalConfig targetDirectory), before the copy out.
SPINAL_STAGING_DIR = $(SPINAL_DIR)/rtl
SPINAL_GEN_DIR = $(SPINAL_REPO_ROOT)/rtl/generated
SPINAL_DOC_DIR = $(SPINAL_REPO_ROOT)/sdk/include/generated
SPINAL_BUILD = $(SPINAL_DIR)/build.sbt $(SPINAL_DIR)/project/build.properties \
               $(SPINAL_DIR)/project/plugins.sbt

SBT ?= sbt

# Per module: its generator object, the Scala files it is built from (keep these in step with the
# code: the crossbar sizes its windows from the register blocks), and its register map files.
SPINAL_MODULES = APBFrontendRegs ApbLutRam ApbThreadRegs Axi4ToApbXbar AxiTileDma AxiVisibilityDma

SPINAL_MAIN_APBFrontendRegs = APBFrontendRegsVerilog
SPINAL_SRCS_APBFrontendRegs = ControlModules/APBFrontendRegs.scala
SPINAL_DOCS_APBFrontendRegs = $(addprefix apb_front_end_regmap.,h json html)

SPINAL_MAIN_ApbLutRam = ApbLutRamVerilog
SPINAL_SRCS_ApbLutRam = ControlModules/APBAddressLUT.scala
SPINAL_DOCS_ApbLutRam =

SPINAL_MAIN_ApbThreadRegs = ApbThreadRegsVerilog
SPINAL_SRCS_ApbThreadRegs = ControlModules/ApbThreadRegs.scala
SPINAL_DOCS_ApbThreadRegs = $(addprefix apb_thread_regmap.,h json html)

SPINAL_MAIN_Axi4ToApbXbar = Axi4ToApbXbarVerilog
SPINAL_SRCS_Axi4ToApbXbar = ControlModules/Axi4ToApbXbar.scala ControlModules/Apb3RegSlice.scala \
                            ControlModules/APBAddressLUT.scala ControlModules/APBFrontendRegs.scala \
                            ControlModules/ApbThreadRegs.scala
SPINAL_DOCS_Axi4ToApbXbar = address_map.json

SPINAL_MAIN_AxiTileDma = AxiTileDmaVerilog
SPINAL_SRCS_AxiTileDma = TileDMA/AxiTileDma.scala
SPINAL_DOCS_AxiTileDma = $(addprefix axi_tile_dma_regmap.,h json html)

SPINAL_MAIN_AxiVisibilityDma = AxiVisibilityDmaVerilog
SPINAL_SRCS_AxiVisibilityDma = VisDMA/AxiVisibilityDma.scala
SPINAL_DOCS_AxiVisibilityDma = $(addprefix axi_visibility_dma_regmap.,h json html)

SPINAL_VERILOG = $(SPINAL_MODULES:%=$(SPINAL_GEN_DIR)/%.v)
SPINAL_DOCS = $(foreach m,$(SPINAL_MODULES),$(addprefix $(SPINAL_DOC_DIR)/$(m)/,$(SPINAL_DOCS_$(m))))

# Copy files $(1) into directory $(2), and delete a directory.
SPINAL_COMMA := ,
SPINAL_SPACE := $(subst ,, )
ifeq ($(OS),Windows_NT)
SPINAL_COPY = powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path '$(2)' | Out-Null; Copy-Item -Force $(subst $(SPINAL_SPACE),$(SPINAL_COMMA),$(foreach f,$(1),'$(f)')) -Destination '$(2)'"
SPINAL_RMDIR = powershell -NoProfile -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue '$(1)'; exit 0"
else
SPINAL_COPY = mkdir -p '$(2)' && cp -f $(1) '$(2)'
SPINAL_RMDIR = rm -rf '$(1)'
endif

# Module $(1)'s register maps to SPINAL_DOC_DIR; nothing for a module without any.
spinal_copy_docs = $(if $(SPINAL_DOCS_$(1)),$(call SPINAL_COPY,$(addprefix $(SPINAL_STAGING_DIR)/$(1)/,$(SPINAL_DOCS_$(1))),$(SPINAL_DOC_DIR)/$(1)))

# Including this file must not change the includer's default goal.
SPINAL_SAVED_GOAL := $(.DEFAULT_GOAL)

.PHONY: spinal
spinal: $(SPINAL_VERILOG) $(SPINAL_DOCS)

# $(1): module. Its outputs are one group: one sbt run makes all of them.
define SPINAL_MODULE_RULE
$(SPINAL_GEN_DIR)/$(1).v $(addprefix $(SPINAL_DOC_DIR)/$(1)/,$(SPINAL_DOCS_$(1))) &: \
    $(SPINAL_BUILD) $(addprefix $(SPINAL_SRC_DIR)/,$(SPINAL_SRCS_$(1)))
	$$(call SPINAL_RMDIR,$(SPINAL_STAGING_DIR)/$(1))
	cd $(SPINAL_DIR) && $(SBT) -batch "runMain lviv_gpu_modules.$(SPINAL_MAIN_$(1))"
	$$(call SPINAL_COPY,$(SPINAL_STAGING_DIR)/$(1)/$(1).v,$(SPINAL_GEN_DIR))
	$$(call spinal_copy_docs,$(1))
endef

$(foreach m,$(SPINAL_MODULES),$(eval $(call SPINAL_MODULE_RULE,$(m))))

.DEFAULT_GOAL := $(SPINAL_SAVED_GOAL)
