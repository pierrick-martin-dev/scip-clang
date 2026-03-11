# Makefile for scip-clang
#
# This is a simple build system to replace Bazel. It expects dependencies
# to be provided via environment variables (set by flake.nix or manually).
#
# Required env vars (set by nix develop / nix build):
#   LLVM_DEV, LLVM_LIB, CLANG_DEV, CLANG_LIB, LLVM_CONFIG
#   PROTOBUF_PREFIX, ABSEIL_PREFIX, SPDLOG_PREFIX
#   RAPIDJSON_INCLUDE, CXXOPTS_INCLUDE, WYHASH_INCLUDE
#   UTFCPP_INCLUDE, PERFETTO_SDK, SCIP_PROTO_DIR
#   BOOST_INCLUDE, BOOST_LIB
#   PROTOC
#
# Optional (for tests):
#   DOCTEST_INCLUDE, DTL_INCLUDE

CXX         ?= c++
PROTOC      ?= protoc
LLVM_CONFIG ?= llvm-config
BUILDDIR    ?= build

# ── Compiler flags ──────────────────────────────────────────────────
CXXFLAGS := -std=c++20 -O2 -DFORCE_DEBUG=1 -DNDEBUG
CXXFLAGS += -DSPDLOG_COMPILED_LIB
CXXFLAGS += -DRAPIDJSON_HAS_STDSTRING
CXXFLAGS += -DRAPIDJSON_HAS_CXX11_RANGE_FOR
CXXFLAGS += -DRAPIDJSON_HAS_CXX11_RVALUE_REFS
CXXFLAGS += -DRAPIDJSON_HAS_CXX11_TYPETRAITS
CXXFLAGS += -Wall -Wextra

# ── Include paths ───────────────────────────────────────────────────
INCLUDES := -I.
INCLUDES += -I$(BUILDDIR)/gen
INCLUDES += -I$(BUILDDIR)/gen/scip
INCLUDES += -I$(LLVM_DEV)/include
INCLUDES += -I$(CLANG_DEV)/include
INCLUDES += -I$(PROTOBUF_PREFIX)/include
INCLUDES += -I$(ABSEIL_PREFIX)/include
INCLUDES += -I$(SPDLOG_PREFIX)/include
INCLUDES += -I$(BOOST_INCLUDE)
INCLUDES += -I$(RAPIDJSON_INCLUDE)
INCLUDES += -I$(CXXOPTS_INCLUDE)
INCLUDES += -I$(WYHASH_INCLUDE)
INCLUDES += -I$(BUILDDIR)/third_party

# Test-only include paths
TEST_INCLUDES := $(INCLUDES)
ifdef DOCTEST_INCLUDE
  TEST_INCLUDES += -I$(DOCTEST_INCLUDE)
endif
ifdef DTL_INCLUDE
  TEST_INCLUDES += -I$(DTL_INCLUDE)
endif

# ── Sources ─────────────────────────────────────────────────────────
INDEXER_SRCS := \
	indexer/ApproximateNameResolver.cc \
	indexer/AstConsumer.cc \
	indexer/CliOptions.cc \
	indexer/CommandLineCleaner.cc \
	indexer/Comparison.cc \
	indexer/CompilationDatabase.cc \
	indexer/DebugHelpers.cc \
	indexer/Driver.cc \
	indexer/Enforce.cc \
	indexer/Exception.cc \
	indexer/FileSystem.cc \
	indexer/IdPathMappings.cc \
	indexer/Indexer.cc \
	indexer/IpcMessages.cc \
	indexer/JsonIpcQueue.cc \
	indexer/LlvmCommandLineParsing.cc \
	indexer/Logging.cc \
	indexer/PackageMap.cc \
	indexer/Path.cc \
	indexer/Preprocessing.cc \
	indexer/ProgressReporter.cc \
	indexer/ScipExtras.cc \
	indexer/Statistics.cc \
	indexer/SymbolFormatter.cc \
	indexer/SymbolName.cc \
	indexer/Timer.cc \
	indexer/Tracing.cc \
	indexer/Worker.cc \
	indexer/os/Os.cc

# Platform-specific sources
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  INDEXER_SRCS += indexer/os/Linux.cc
else ifeq ($(UNAME_S),Darwin)
  INDEXER_SRCS += indexer/os/macOS.cc
endif

MAIN_SRC := indexer/main.cc

# Test sources
TEST_SRCS := test/test_main.cc test/Snapshot.cc
IPC_TEST_SRCS := test/ipc_test_main.cc

# Generated protobuf sources
PROTO_SRCS := \
	$(BUILDDIR)/gen/proto/fwd_decls.pb.cc \
	$(BUILDDIR)/gen/scip/scip/scip.pb.cc

# Perfetto SDK (single-file)
PERFETTO_SRC := $(BUILDDIR)/third_party/perfetto/perfetto.cc

# ── Object files ────────────────────────────────────────────────────
INDEXER_OBJS := $(patsubst %.cc,$(BUILDDIR)/%.o,$(INDEXER_SRCS))
MAIN_OBJ     := $(BUILDDIR)/main.o
PROTO_OBJS   := $(patsubst %.cc,%.o,$(PROTO_SRCS))
PERFETTO_OBJ := $(BUILDDIR)/third_party/perfetto/perfetto.o
TEST_OBJS    := $(patsubst %.cc,$(BUILDDIR)/%.o,$(TEST_SRCS))
IPC_TEST_OBJS := $(patsubst %.cc,$(BUILDDIR)/%.o,$(IPC_TEST_SRCS))

ALL_OBJS := $(MAIN_OBJ) $(INDEXER_OBJS) $(PROTO_OBJS) $(PERFETTO_OBJ)

# Library objects = everything except main (shared between scip-clang and tests)
LIB_OBJS := $(INDEXER_OBJS) $(PROTO_OBJS) $(PERFETTO_OBJ)

# ── Static libraries to link ───────────────────────────────────────
# Clang static libs (order matters)
CLANG_STATIC_LIBS := \
	clangTooling clangFrontend clangSerialization clangDriver \
	clangParse clangSema clangAPINotes clangAnalysis clangEdit clangFormat \
	clangASTMatchers clangAST clangLex clangBasic clangSupport

# LLVM: use llvm-config for complete dependency-ordered list
LLVM_LINK_FLAGS := $(shell $(LLVM_CONFIG) --link-static --libs all)
LLVM_SYSTEM_LIBS := $(shell $(LLVM_CONFIG) --link-static --system-libs)

# Abseil static libs (comprehensive list to cover all transitive deps from protobuf)
ABSL_STATIC_LIBS := \
	absl_log_internal_message absl_log_internal_check_op \
	absl_log_internal_conditions absl_log_internal_nullguard \
	absl_log_internal_log_sink_set absl_log_internal_globals \
	absl_log_internal_format absl_log_internal_fnmatch \
	absl_log_internal_proto \
	absl_log_entry absl_log_sink absl_log_globals absl_log_flags \
	absl_log_initialize absl_log_severity \
	absl_die_if_null absl_examine_stack \
	absl_flags_commandlineflag absl_flags_commandlineflag_internal \
	absl_flags_config absl_flags_internal absl_flags_marshalling \
	absl_flags_parse absl_flags_private_handle_accessor \
	absl_flags_program_name absl_flags_reflection \
	absl_flags_usage absl_flags_usage_internal \
	absl_status absl_statusor absl_strerror \
	absl_str_format_internal absl_strings absl_strings_internal \
	absl_string_view \
	absl_cord absl_cord_internal absl_cordz_functions \
	absl_cordz_handle absl_cordz_info absl_cordz_sample_token \
	absl_crc32c absl_crc_cord_state absl_crc_cpu_detect absl_crc_internal \
	absl_int128 absl_throw_delegate absl_raw_logging_internal \
	absl_spinlock_wait absl_base \
	absl_failure_signal_handler absl_symbolize absl_stacktrace \
	absl_debugging_internal absl_demangle_internal absl_demangle_rust \
	absl_decode_rust_punycode absl_utf8_for_code_point \
	absl_malloc_internal absl_hash absl_city absl_low_level_hash \
	absl_raw_hash_set absl_hashtablez_sampler \
	absl_synchronization absl_graphcycles_internal absl_kernel_timeout_internal \
	absl_time absl_civil_time absl_time_zone \
	absl_exponential_biased absl_periodic_sampler absl_poison \
	absl_random_distributions absl_random_internal_platform \
	absl_random_internal_pool_urbg absl_random_internal_randen \
	absl_random_internal_randen_hwaes absl_random_internal_randen_hwaes_impl \
	absl_random_internal_randen_slow absl_random_internal_seed_material \
	absl_random_seed_gen_exception absl_random_seed_sequences \
	absl_bad_any_cast_impl absl_bad_optional_access absl_bad_variant_access \
	absl_leak_check absl_vlog_config_internal

# Build the linker flags: prefer static .a, fall back to skipping
define find_static_lib
$(wildcard $(1)/lib/lib$(2).a)
endef

LINK_CLANG := $(foreach lib,$(CLANG_STATIC_LIBS),$(call find_static_lib,$(CLANG_LIB),$(lib)))
LINK_LLVM  := -L$(LLVM_LIB)/lib $(LLVM_LINK_FLAGS)
LINK_ABSL  := -Wl,--start-group $(foreach lib,$(ABSL_STATIC_LIBS),$(call find_static_lib,$(ABSEIL_PREFIX),$(lib))) -Wl,--end-group

# Protobuf static libs (may be in lib/ or lib64/)
LINK_PROTO := $(wildcard $(PROTOBUF_PREFIX)/lib/libprotobuf.a) \
              $(wildcard $(PROTOBUF_PREFIX)/lib64/libprotobuf.a) \
              $(wildcard $(PROTOBUF_PREFIX)/lib/libutf8_validity.a) \
              $(wildcard $(PROTOBUF_PREFIX)/lib64/libutf8_validity.a) \
              $(wildcard $(PROTOBUF_PREFIX)/lib/libutf8_range.a) \
              $(wildcard $(PROTOBUF_PREFIX)/lib64/libutf8_range.a)

LINK_SPDLOG := $(SPDLOG_PREFIX)/lib/libspdlog.a

LINK_BOOST := -L$(BOOST_LIB) -lboost_date_time -lboost_filesystem

LINK_SYSTEM := $(LLVM_SYSTEM_LIBS) -lpthread -ldl -lrt -lm -lstdc++

# Common link libs (shared between main binary and test binaries)
# Order matters: protobuf depends on abseil, so protobuf must come first
LINK_ALL_LIBS := \
	$(LINK_CLANG) $(LINK_LLVM) \
	$(LINK_PROTO) $(LINK_ABSL) $(LINK_SPDLOG) \
	$(LINK_BOOST) $(LINK_SYSTEM)

# ── Targets ─────────────────────────────────────────────────────────
.PHONY: all clean gen test-binaries

all: $(BUILDDIR)/scip-clang

test-binaries: $(BUILDDIR)/scip-clang $(BUILDDIR)/test_main $(BUILDDIR)/ipc_test_main

# Protobuf code generation
gen: $(PROTO_SRCS)

$(BUILDDIR)/gen/proto/fwd_decls.pb.cc $(BUILDDIR)/gen/proto/fwd_decls.pb.h: proto/fwd_decls.proto
	@mkdir -p $(BUILDDIR)/gen/proto
	$(PROTOC) --proto_path=proto --cpp_out=$(BUILDDIR)/gen/proto proto/fwd_decls.proto

$(BUILDDIR)/gen/scip/scip/scip.pb.cc $(BUILDDIR)/gen/scip/scip/scip.pb.h: $(SCIP_PROTO_DIR)/scip.proto
	@mkdir -p $(BUILDDIR)/gen/scip/scip
	$(PROTOC) --proto_path=$(SCIP_PROTO_DIR) --cpp_out=$(BUILDDIR)/gen/scip/scip $(SCIP_PROTO_DIR)/scip.proto

# Prepare perfetto SDK (copy + patch)
$(PERFETTO_SRC): $(PERFETTO_SDK)/perfetto.cc $(PERFETTO_SDK)/perfetto.h
	@mkdir -p $(BUILDDIR)/third_party/perfetto
	cp $(PERFETTO_SDK)/perfetto.cc $(BUILDDIR)/third_party/perfetto/
	cp $(PERFETTO_SDK)/perfetto.h $(BUILDDIR)/third_party/perfetto/
	-patch -p1 -d $(BUILDDIR)/third_party/perfetto < third_party/perfetto.patch

# Prepare utfcpp headers (Bazel uses strip_include_prefix + include_prefix)
# source/utf8.h -> utfcpp/utf8.h
UTFCPP_LINK := $(BUILDDIR)/third_party/utfcpp
$(UTFCPP_LINK): $(UTFCPP_INCLUDE)
	@mkdir -p $(BUILDDIR)/third_party
	ln -sfn $(UTFCPP_INCLUDE) $(UTFCPP_LINK)

# ── Compilation rules ───────────────────────────────────────────────

# Ensure perfetto headers and proto headers are ready before any indexer compilation.
# This prevents parallel build races where .cc files include perfetto/perfetto.h
# or generated .pb.h before those files are prepared.
PROTO_HEADERS := $(BUILDDIR)/gen/proto/fwd_decls.pb.h $(BUILDDIR)/gen/scip/scip/scip.pb.h
$(INDEXER_OBJS) $(MAIN_OBJ): | $(PERFETTO_SRC) $(PROTO_HEADERS) $(UTFCPP_LINK)
$(TEST_OBJS) $(IPC_TEST_OBJS): | $(PERFETTO_SRC) $(PROTO_HEADERS) $(UTFCPP_LINK)

# Perfetto (no project includes needed, just its own header)
$(PERFETTO_OBJ): $(PERFETTO_SRC)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -I$(BUILDDIR)/third_party/perfetto -c $< -o $@

# Generated protobuf objects
$(BUILDDIR)/gen/proto/fwd_decls.pb.o: $(BUILDDIR)/gen/proto/fwd_decls.pb.cc
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

$(BUILDDIR)/gen/scip/scip/scip.pb.o: $(BUILDDIR)/gen/scip/scip/scip.pb.cc
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

# Indexer sources
$(BUILDDIR)/indexer/%.o: indexer/%.cc
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

# main.cc
$(MAIN_OBJ): $(MAIN_SRC)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

# Doctest implementation object (provides doctest symbols for test binaries)
DOCTEST_IMPL_SRC := $(BUILDDIR)/doctest_impl.cc
DOCTEST_IMPL_OBJ := $(BUILDDIR)/doctest_impl.o

$(DOCTEST_IMPL_SRC):
	@mkdir -p $(dir $@)
	@echo '#define DOCTEST_CONFIG_IMPLEMENT' > $@
	@echo '#include "doctest/doctest.h"' >> $@

$(DOCTEST_IMPL_OBJ): $(DOCTEST_IMPL_SRC)
	$(CXX) $(CXXFLAGS) $(TEST_INCLUDES) -c $< -o $@

# Test compilation flags: doctest symbols come from doctest_impl.o
TEST_DEFINES := -DDOCTEST_CONFIG_IMPLEMENTATION_IN_DLL -DDOCTEST_CONFIG_NO_UNPREFIXED_OPTIONS

# Test sources
$(BUILDDIR)/test/%.o: test/%.cc
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(TEST_DEFINES) $(TEST_INCLUDES) -c $< -o $@

# ── Link: main binary ──────────────────────────────────────────────
$(BUILDDIR)/scip-clang: $(ALL_OBJS)
	@echo "Linking $@..."
	$(CXX) -O2 -o $@ $(ALL_OBJS) $(LINK_ALL_LIBS)
	@echo "Done: $@ ($$(du -h $@ | cut -f1))"

# ── Link: test binaries ────────────────────────────────────────────
$(BUILDDIR)/test_main: $(TEST_OBJS) $(DOCTEST_IMPL_OBJ) $(LIB_OBJS)
	@echo "Linking $@..."
	$(CXX) -O2 -o $@ $(TEST_OBJS) $(DOCTEST_IMPL_OBJ) $(LIB_OBJS) $(LINK_ALL_LIBS)
	@echo "Done: $@"

$(BUILDDIR)/ipc_test_main: $(IPC_TEST_OBJS) $(LIB_OBJS)
	@echo "Linking $@..."
	$(CXX) -O2 -o $@ $(IPC_TEST_OBJS) $(LIB_OBJS) $(LINK_ALL_LIBS)
	@echo "Done: $@"

# ── Test runner ─────────────────────────────────────────────────────
# Usage: make test
#   Runs all test kinds. Requires test-binaries to be built first.
#   The scip-clang binary must be at $(BUILDDIR)/scip-clang for index
#   and robustness tests (they spawn it as a subprocess).
.PHONY: test test-unit test-compdb test-index test-preprocessor test-robustness test-ipc

# Symlink scip-clang into indexer/ where test_main expects to find it
$(BUILDDIR)/indexer-scip-clang-link: $(BUILDDIR)/scip-clang
	@mkdir -p indexer
	ln -sfn $(abspath $(BUILDDIR)/scip-clang) indexer/scip-clang
	@touch $@

TEST_INDEX_CASES := aliases crossrepo cuda docs functions fwd_decl macros namespaces types vars
TEST_PREPROCESSOR_CASES := hashinclude ill_behaved already_preprocessed
TEST_ROBUSTNESS_CASES := crash sleep spin

test-unit: $(BUILDDIR)/test_main
	$(BUILDDIR)/test_main --test-kind=unit

test-compdb: $(BUILDDIR)/test_main
	$(BUILDDIR)/test_main --test-kind=compdb

test-index: $(BUILDDIR)/test_main $(BUILDDIR)/indexer-scip-clang-link
	@for name in $(TEST_INDEX_CASES); do \
		echo "=== index/$$name ==="; \
		$(BUILDDIR)/test_main --test-kind=index --test-name=$$name || exit 1; \
	done

test-preprocessor: $(BUILDDIR)/test_main $(BUILDDIR)/indexer-scip-clang-link
	@for name in $(TEST_PREPROCESSOR_CASES); do \
		echo "=== preprocessor/$$name ==="; \
		$(BUILDDIR)/test_main --test-kind=preprocessor --test-name=$$name || exit 1; \
	done

test-robustness: $(BUILDDIR)/test_main $(BUILDDIR)/indexer-scip-clang-link
	@for name in $(TEST_ROBUSTNESS_CASES); do \
		echo "=== robustness/$$name ==="; \
		$(BUILDDIR)/test_main --test-kind=robustness --test-name=$$name || exit 1; \
	done

test-ipc: $(BUILDDIR)/ipc_test_main
	$(BUILDDIR)/ipc_test_main --hang
	$(BUILDDIR)/ipc_test_main --crash

test: test-unit test-compdb test-index test-preprocessor test-robustness test-ipc
	@echo "All tests passed."

# ── Snapshot update ─────────────────────────────────────────────────
.PHONY: update-snapshots update-index update-preprocessor update-compdb update-robustness

update-index: $(BUILDDIR)/test_main $(BUILDDIR)/indexer-scip-clang-link
	@for name in $(TEST_INDEX_CASES); do \
		echo "=== update index/$$name ==="; \
		$(BUILDDIR)/test_main --test-kind=index --test-name=$$name --update || exit 1; \
	done

update-preprocessor: $(BUILDDIR)/test_main $(BUILDDIR)/indexer-scip-clang-link
	@for name in $(TEST_PREPROCESSOR_CASES); do \
		echo "=== update preprocessor/$$name ==="; \
		$(BUILDDIR)/test_main --test-kind=preprocessor --test-name=$$name --update || exit 1; \
	done

update-compdb: $(BUILDDIR)/test_main
	$(BUILDDIR)/test_main --test-kind=compdb --update

update-robustness: $(BUILDDIR)/test_main $(BUILDDIR)/indexer-scip-clang-link
	@for name in $(TEST_ROBUSTNESS_CASES); do \
		echo "=== update robustness/$$name ==="; \
		$(BUILDDIR)/test_main --test-kind=robustness --test-name=$$name --update || exit 1; \
	done

update-snapshots: update-index update-preprocessor update-compdb update-robustness
	@echo "All snapshots updated."

clean:
	rm -rf $(BUILDDIR)
	rm -f indexer/scip-clang
