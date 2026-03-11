{
  description = "scip-clang - SCIP indexer for C/C++ using Clang";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opencode.url = "github:anomalyco/opencode";
  };

  outputs = { self, nixpkgs, flake-utils, opencode, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        llvmPkgs = pkgs.llvmPackages; # 21.x, matches project's LLVM commit

        # ── Third-party sources (commits/versions from fetch_deps.bzl) ──────

        protobuf-src = pkgs.fetchFromGitHub {
          owner = "protocolbuffers";
          repo = "protobuf";
          rev = "v25.3";
          hash = "sha256-N/mO9a6NyC0GwxY3/u1fbFbkfH7NTkyuIti6L3bc+7k=";
        };

        abseil-src = pkgs.fetchFromGitHub {
          owner = "abseil";
          repo = "abseil-cpp";
          rev = "20240722.0";
          hash = "sha256-51jpDhdZ0n+KLmxh8KVaTz53pZAB0dHjmILFX+OLud4=";
        };

        spdlog-src = pkgs.fetchFromGitHub {
          owner = "gabime";
          repo = "spdlog";
          rev = "486b55554f11c9cccc913e11a87085b2a91f706f"; # v1.16.0
          hash = "sha256-VB82cNfpJlamUjrQFYElcy0CXAbkPqZkD5zhuLeHLzs=";
        };

        perfetto-src = pkgs.fetchFromGitHub {
          owner = "google";
          repo = "perfetto";
          rev = "v33.1";
          hash = "sha256-16cm4AQ7BPK9XK2luZV9JqFqDAJ34DUOfuMsqEubKSc=";
        };

        scip-src = pkgs.fetchFromGitHub {
          owner = "sourcegraph";
          repo = "scip";
          rev = "75e68ad1bbd31af3eccab4d034428e2d06795296";
          hash = "sha256-rwpIQbvcEul8GnwGM048+gM03FJPRVyeDf1TW/CNwb0=";
        };

        rapidjson-src = pkgs.fetchFromGitHub {
          owner = "Tencent";
          repo = "rapidjson";
          rev = "a98e99992bd633a2736cc41f96ec85ef0c50e44d";
          hash = "sha256-p0SH5dKkN4NQQaGX0EWTkN90yT0VjrzsbILw3r93qtM=";
        };

        cxxopts-src = pkgs.fetchFromGitHub {
          owner = "jarro2783";
          repo = "cxxopts";
          rev = "v3.0.0";
          hash = "sha256-RpXSbqgEFDj3yGXgS1HqGroK32MJ7TwykLwHikyQpyM=";
        };

        wyhash-src = pkgs.fetchFromGitHub {
          owner = "wangyi-fudan";
          repo = "wyhash";
          rev = "ea3b25e1aef55d90f707c3a292eeb9162e2615d8";
          hash = "sha256-/FkVumXtf6fY+pnzyiqQ+JocR4IazZMyv7uLydyBXZ0=";
        };

        utfcpp-src = pkgs.fetchFromGitHub {
          owner = "nemtrif";
          repo = "utfcpp";
          rev = "v4.0.5";
          hash = "sha256-oKVFUjCvkHjqifZe98aUe68IBUaAZYWU2S2rxyAA9Cg=";
        };

        # Test-only dependencies
        doctest-src = pkgs.fetchFromGitHub {
          owner = "doctest";
          repo = "doctest";
          rev = "v2.4.9";
          hash = "sha256-ugmkeX2PN4xzxAZpWgswl4zd2u125Q/ADSKzqTfnd94=";
        };

        dtl-src = pkgs.fetchFromGitHub {
          owner = "cubicdaiya";
          repo = "dtl";
          rev = "v1.21";
          hash = "sha256-s+syRiJhcxvmE0FBcbCi6DrL1hwu+0IJNMgg5Tldsv4=";
        };

        # ── Protobuf 25.3 built from source ─────────────────────────────────
        protobuf = pkgs.stdenv.mkDerivation {
          pname = "protobuf";
          version = "25.3";
          src = protobuf-src;
          nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
          buildInputs = [ pkgs.zlib abseil ];
          cmakeFlags = [
            "-Dprotobuf_BUILD_TESTS=OFF"
            "-Dprotobuf_BUILD_SHARED_LIBS=OFF"
            "-Dprotobuf_ABSL_PROVIDER=package"
            "-DCMAKE_CXX_STANDARD=20"
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
          ];
        };

        # ── Abseil 20240722.0 built from source ─────────────────────────────
        abseil = pkgs.stdenv.mkDerivation {
          pname = "abseil-cpp";
          version = "20240722.0";
          src = abseil-src;
          nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
          cmakeFlags = [
            "-DCMAKE_CXX_STANDARD=20"
            "-DABSL_BUILD_TESTING=OFF"
            "-DBUILD_SHARED_LIBS=OFF"
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
          ];
        };

        # ── spdlog 1.16.0 built from source (bundled fmt) ───────────────────
        spdlog = pkgs.stdenv.mkDerivation {
          pname = "spdlog";
          version = "1.16.0";
          src = spdlog-src;
          nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
          cmakeFlags = [
            "-DSPDLOG_BUILD_SHARED=OFF"
            "-DSPDLOG_FMT_EXTERNAL=OFF"
            "-DCMAKE_CXX_STANDARD=20"
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
          ];
        };

        # ── scip-clang ──────────────────────────────────────────────────────
        scip-clang = llvmPkgs.stdenv.mkDerivation {
          pname = "scip-clang";
          version = "0.4.1";
          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = [ pkgs.gnumake llvmPkgs.llvm.dev ];

          buildInputs = [
            llvmPkgs.llvm.lib
            llvmPkgs.llvm.dev
            llvmPkgs.libclang.lib
            llvmPkgs.libclang.dev
            protobuf
            abseil
            spdlog
            pkgs.boost183
            pkgs.zlib
            pkgs.libxml2
          ];

          # Wire all dependency paths into the Makefile via env vars
          makeFlags = [
            "BUILDDIR=build"
            "LLVM_DEV=${llvmPkgs.llvm.dev}"
            "LLVM_LIB=${llvmPkgs.llvm.lib}"
            "LLVM_CONFIG=${llvmPkgs.llvm.dev}/bin/llvm-config"
            "CLANG_DEV=${llvmPkgs.libclang.dev}"
            "CLANG_LIB=${llvmPkgs.libclang.lib}"
            "PROTOBUF_PREFIX=${protobuf}"
            "ABSEIL_PREFIX=${abseil}"
            "SPDLOG_PREFIX=${spdlog}"
            "BOOST_INCLUDE=${pkgs.boost183.dev}/include"
            "BOOST_LIB=${pkgs.boost183}/lib"
            "RAPIDJSON_INCLUDE=${rapidjson-src}/include"
            "CXXOPTS_INCLUDE=${cxxopts-src}/include"
            "WYHASH_INCLUDE=${wyhash-src}"
            "UTFCPP_INCLUDE=${utfcpp-src}/source"
            "PERFETTO_SDK=${perfetto-src}/sdk"
            "SCIP_PROTO_DIR=${scip-src}"
            "PROTOC=${protobuf}/bin/protoc"
          ];

          enableParallelBuilding = true;

          installPhase = ''
            mkdir -p $out/bin
            cp build/scip-clang $out/bin/
          '';

          meta = with pkgs.lib; {
            description = "SCIP indexer for C/C++ using Clang";
            homepage = "https://github.com/sourcegraph/scip-clang";
            license = licenses.asl20;
            platforms = platforms.linux ++ platforms.darwin;
          };
        };

      in {
        packages.default = scip-clang;
        packages.scip-clang = scip-clang;

        devShells.default = (pkgs.mkShell.override { stdenv = llvmPkgs.stdenv; }) {
          inputsFrom = [ scip-clang ];
          packages = [
            opencode.packages.${system}.opencode
            pkgs.git
          ];
          buildInputs = [
            pkgs.libxml2
          ];

          # Set env vars so `make` works in the dev shell
          LLVM_DEV = "${llvmPkgs.llvm.dev}";
          LLVM_LIB = "${llvmPkgs.llvm.lib}";
          LLVM_CONFIG = "${llvmPkgs.llvm.dev}/bin/llvm-config";
          CLANG_DEV = "${llvmPkgs.libclang.dev}";
          CLANG_LIB = "${llvmPkgs.libclang.lib}";
          PROTOBUF_PREFIX = "${protobuf}";
          ABSEIL_PREFIX = "${abseil}";
          SPDLOG_PREFIX = "${spdlog}";
          BOOST_INCLUDE = "${pkgs.boost183.dev}/include";
          BOOST_LIB = "${pkgs.boost183}/lib";
          RAPIDJSON_INCLUDE = "${rapidjson-src}/include";
          CXXOPTS_INCLUDE = "${cxxopts-src}/include";
          WYHASH_INCLUDE = "${wyhash-src}";
          UTFCPP_INCLUDE = "${utfcpp-src}/source";
          PERFETTO_SDK = "${perfetto-src}/sdk";
          SCIP_PROTO_DIR = "${scip-src}";
          PROTOC = "${protobuf}/bin/protoc";
          DOCTEST_INCLUDE = "${doctest-src}";
          DTL_INCLUDE = "${dtl-src}";

          shellHook = ''
            echo "scip-clang dev shell"
            echo "  make                  - build scip-clang"
            echo "  make test-binaries    - build scip-clang + test binaries"
            echo "  make test             - run all tests"
            echo "  make update-snapshots - regenerate all snapshots"
            echo "  nix build             - build via nix derivation"
            echo "  opencode              - coding assistant"
          '';
        };
      });
}
