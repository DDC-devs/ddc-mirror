# The DDC build system.

# -----------------------------------------------------------------------------
# (Build targets)
#   all                 -- build the compiler and libs (default)
#
#   total               -- build the compiler, libs, docs and run all the tests.
#   cleantotal          -- same as above, but do a full clean first.
#
#   deps                -- build dependencies.
#   runtime		-- build the runtime system.
#   libs		-- build base libraries.
#   docs		-- build Haddock docks.
#   bin/ddc             -- build the compiler binary.
#   bin/ddci-core       -- build the interactive shell for the Core languages.
#   bin/ddci-tetra	-- build the interactive shell for the Tetra language.
#   bin/war             -- build the test driver.
#   bin/plate           -- build the boilerplate generator.
#
# (Running just the regression tests)
#   (interactive versions)
#   war			-- run the minimal testing required before pushing patches.
#   llvmwar		-- llvm backend only version of the 'war' target. 
#   totalwar       	-- run tests in all possible ways. 
#
#   (non-interactive versions)
#   logwar         	-- same as above, logging failures to war.failed.
#   batchwar       	-- run all tests in all ways.
#
# (Working with Cabal)
#   packages            -- build and install all the Cabal packages.
#   packages-unregister -- unregister all the Cabal packages.
#
# (Cleaning up)
#   clean               -- clean everything.
#   cleanWar            -- clean libraries and tests.
#   cleanRuntime        -- clean the runtime system.
#   cleanLibrary        -- clean out the libraries.
#

# -- Meta Targets -------------------------------------------------------------
#    These may recursively invoke make to do several things.
#    These are the ONLY instances of recursive makes in the system.

# -- Build the compiler and libs
.PHONY	: all
all 	:
	@$(MAKE) allWithConfig


# Include all the configuration.
# These need to come before all the rules after this point in the Makefile.
include make/build.mk


# Build everything related to alpha and new compiler.
# now that we have the configuration included above.
.PHONY	: allWithConfig
allWithConfig :
	@$(MAKE) deps
	@$(MAKE) bin/ddc bin/ddc-check bin/ddci-core bin/ddci-tetra \
		 runtime bin/war -j $(THREADS)


# Build everything related to the new compiler, 
# now that we have the configuration included above.
.PHONY	: newWithConfig
newWithConfig :
	@$(MAKE) deps-new
	@$(MAKE) bin/ddc bin/ddc-check bin/ddci-core bin/ddci-tetra \
		 runtime bin/war -j $(THREADS)


# -- Build the compiler, libs, docs, and run all the tests in all ways (slow)
.PHONY  : total
total	:
	@$(MAKE) allWithConfig
	@$(MAKE) docs
	@$(MAKE) batchwar


# -- Same as 'total', but do a full clean first
.PHONY  : cleantotal
cleantotal :
	@$(MAKE) clean
	@$(MAKE) total


# -- Build all dependencies
.PHONY	: deps
deps	: make/deps/Makefile-ddc-check.deps \
          make/deps/Makefile-ddc-main.deps \
          make/deps/Makefile-ddci-core.deps \
          make/deps/Makefile-ddci-tetra.deps \
          make/deps/Makefile-war.deps

# -- Build all dependencies related to the new compiler
.PHONY	 : deps-new
deps-new : make/deps/Makefile-ddc-check.deps \
           make/deps/Makefile-ddc-main.deps \
           make/deps/Makefile-ddci-core.deps \
           make/deps/Makefile-ddci-tetra.deps \
           make/deps/Makefile-war.deps


# -- What to do during the nightly builds
.PHONY  : nightly
nightly :
	@date
	@echo
	@echo "                              DDC Nightly build"
	@echo "------------------------------------------------------------------------------------"
	@$(MAKE) --version
	@echo
	@gcc --version
	@echo
	@$(GHC) --version
	@echo
	@alex --version
	@echo
	@ghc-pkg list | grep "QuickCheck\|regex-base\|regex-posix\|regex-compat\|haskell-src\|parsec\|buildbox\|text"
	@echo
	@sh -c 'llc --version || exit 0'
	@echo
	@echo "------------------------------------------------------------------------------------"
	@$(MAKE) cleantotal


# -- Real Targets -------------------------------------------------------------
#    These don't recursively invoke make.
#
include make/targets/plate.mk
include make/targets/external.mk
include make/targets/runtime.mk
include make/targets/docs.mk
include make/targets/war.mk
include make/targets/lint.mk
include make/targets/tarball.mk
include make/targets/clean.mk
include make/targets/ddc-check.mk
include make/targets/ddc-main.mk
include make/targets/ddci-core.mk
include make/targets/ddci-tetra.mk
include make/targets/helper.mk
include make/targets/packages.mk


# -- Include magic ------------------------------------------------------------
include make/rules.mk
-include runtime/*.dep

# We include Makefile.deps.inc here instead of Makefile.deps directly.
#   Stupid GNU make treats missing files as dependencies, and if they are
#   missing it tries to build them. This causes dependencies to be built
#   even when we do a "make clean"
#
#   This behavior is different to the documentation which says
#   that missing -included files should be ignored.
#
-include make/deps/Makefile-ddc-check.deps.inc
-include make/deps/Makefile-ddc-main.deps.inc
-include make/deps/Makefile-ddci-core.deps.inc
-include make/deps/Makefile-ddci-tetra.deps.inc
-include make/deps/Makefile-war.deps.inc

