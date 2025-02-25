# Unit tests for internal helper functions
using Test
using ReTestItems

@testset "internals.jl" verbose=true begin

@testset "get_starting_testitems" begin
    using ReTestItems: get_starting_testitems, TestItems, @testitem
    graph = ReTestItems.FileNode("")  # we don't use the graph info for this test
    # we previously saw `BoundsError` with 8 testitems, 5 workers.
    # let's test this exhaustively for 1-10 testitems across 1-10 workers.
    for nworkers in 1:10
        for nitems in 1:10
            testitems = [@testitem("ti-$i", _run=false, begin end) for i in 1:nitems]
            starts = get_starting_testitems(TestItems(graph, testitems, 0), nworkers)
            startitems = [x for x in starts if !isnothing(x)]
            @test length(starts) == nworkers
            @test length(startitems) == min(nworkers, nitems)
            @test allunique(ti.name for ti in startitems)
        end
    end
end

@testset "is_test_file" begin
    using ReTestItems: is_test_file
    @test !is_test_file("test/runtests.jl")
    @test !is_test_file("test/bar.jl")

    @test !is_test_file("test/runtests.csv")
    @test !is_test_file("test/bar/qux.jlx")

    @test is_test_file("foo_test.jl")
    @test is_test_file("foo_tests.jl")
    @test is_test_file("foo-test.jl")
    @test is_test_file("foo-tests.jl")

    @test !is_test_file("foo.jl")

    @test is_test_file("src/foo_test.jl")
    @test is_test_file("./src/foo_test.jl")
    @test is_test_file("../src/foo_test.jl")
    @test is_test_file(abspath("../src/foo_test.jl"))
    @test is_test_file("path/to/my/package/src/foo_test.jl")
    @test is_test_file("path/to/my/package/src/foo-test.jl")

    @test !is_test_file("src/foo.jl")
    @test !is_test_file("./src/foo.jl")
    @test !is_test_file("../src/foo.jl")
    @test !is_test_file(abspath("../src/foo.jl"))
    @test !is_test_file("path/to/my/package/src/foo.jl")
end

@testset "is_testsetup_file" begin
    using ReTestItems: is_testsetup_file
    @test is_testsetup_file("bar_testsetup.jl")
    @test is_testsetup_file("bar_testsetups.jl")
    @test is_testsetup_file("bar-testsetup.jl")
    @test is_testsetup_file("bar-testsetups.jl")
    @test is_testsetup_file("path/to/my/package/src/bar-testsetup.jl")
end

@testset "_is_subproject" begin
    using ReTestItems: _is_subproject
    test_pkg_dir = joinpath(pkgdir(ReTestItems), "test", "packages")
    # Test subpackages in MonoRepo identified as subprojects
    monorepo = joinpath(test_pkg_dir, "MonoRepo.jl")
    monorepo_proj = joinpath(monorepo, "Project.toml")
    @assert isfile(monorepo_proj)
    for pkg in ("B", "C", "D")
        path = joinpath(monorepo, "monorepo_packages", pkg)
        @test _is_subproject(path, monorepo_proj)
    end
    for dir in ("src", "test")
        path = joinpath(monorepo, dir)
        @test !_is_subproject(path, monorepo_proj)
    end
    # Test "test/Project.toml" does cause "test/" to be subproject
    tpf = joinpath(test_pkg_dir, "TestProjectFile.jl")
    tpf_proj = joinpath(tpf, "Project.toml")
    @assert isfile(tpf_proj)
    @assert isfile(joinpath(tpf, "test", "Project.toml"))
    for dir in ("src", "test")
        path = joinpath(tpf, dir)
        @test !_is_subproject(path, tpf_proj)
    end
end

@testset "include_testfiles!" begin

@testset "only requested testfiles included" begin
    using ReTestItems: ReTestItems, include_testfiles!, identify_project, is_test_file
    shouldrun = Returns(true)
    verbose_results = false
    report = false

    # Requesting only non-existent files/dirs should result in no files being included
    ti, setups = include_testfiles!("proj", "/this/file/", ("/this/file/is/not/a/t-e-s-tfile.jl",), shouldrun, verbose_results, report)
    @test isempty(ti.testitems)
    @test isempty(setups)

    ti, setups = include_testfiles!("proj", "/this/file/", ("/this/file/does/not/exist/imaginary_tests.jl",), shouldrun, verbose_results, report)
    @test isempty(ti.testitems)
    @test isempty(setups)

    ti, setups = include_testfiles!("proj", "/this/dir/", ("/this/dir/does/not/exist/", "/this/dir/also/not/exist/"), shouldrun, verbose_results, report)
    @test isempty(ti.testitems)
    @test isempty(setups)

    # Requesting a file that's not a test-file should result in no file being included
    pkg_file = joinpath(pkgdir(ReTestItems), "test", "packages", "NoDeps.jl", "src", "NoDeps.jl")
    @assert isfile(pkg_file)
    project = identify_project(pkg_file)
    ti, setups = include_testfiles!("NoDeps.jl", project, (pkg_file,), shouldrun, verbose_results, report)
    @test isempty(ti.testitems)
    @test isempty(setups)

    # Requesting a dir that has no test-files should result in no file being included
    pkg_src = joinpath(pkgdir(ReTestItems), "test", "packages", "NoDeps.jl", "src")
    @assert all(!is_test_file, readdir(pkg_src))
    project = identify_project(pkg_src)
    ti, setups = include_testfiles!("NoDeps.jl", project, (pkg_src,), shouldrun, verbose_results, report)
    @test isempty(ti.testitems)
    @test isempty(setups)

    # Requesting a test-files should result in the file being included
    pkg_file = joinpath(pkgdir(ReTestItems), "test", "packages", "TestsInSrc.jl", "src", "foo_test.jl")
    @assert isfile(pkg_file) && is_test_file(pkg_file)
    project = identify_project(pkg_file)
    ti, setups = include_testfiles!("TestsInSrc.jl", project, (pkg_file,), shouldrun, verbose_results, report)
    @test length(ti.testitems) == 1
    @test isempty(setups)

    # Requesting a dir that has test-files should result in files being included
    pkg = joinpath(pkgdir(ReTestItems), "test", "packages", "TestsInSrc.jl")
    @assert any(!is_test_file, readdir(joinpath(pkg, "src")))
    project = identify_project(pkg)
    ti, setups = include_testfiles!("TestsInSrc.jl", project, (pkg,), shouldrun, verbose_results, report)
    @test map(x -> x.name, ti.testitems) == ["a1", "a2", "z", "y", "x", "b", "bar", "foo"]
    @test isempty(setups)
end

@testset "testsetup files always included" begin
    using ReTestItems: include_testfiles!, is_test_file, is_testsetup_file
    shouldrun = Returns(true)
    verbose_results = false
    report = false
    proj = joinpath(pkgdir(ReTestItems), "Project.toml")

    test_dir = joinpath(pkgdir(ReTestItems), "test", "testfiles")
    @assert count(is_testsetup_file, readdir(test_dir)) == 1
    file = joinpath(test_dir, "_empty_file.jl")
    @assert isfile(file) && !is_test_file(file)
    ti, setups = include_testfiles!("empty_file", proj, (file,), shouldrun, verbose_results, report)
    @test length(ti.testitems) == 0 # just the testsetup
    @test haskey(setups, :FooSetup)

    # even when higher up in directory tree
    nested_dir = joinpath(pkgdir(ReTestItems), "test", "testfiles", "_nested")
    @assert !any(is_testsetup_file, readdir(nested_dir))
    file = joinpath(nested_dir, "_testitem_test.jl")
    @assert isfile(file)
    ti, setups = include_testfiles!("_nested", proj, (file,), shouldrun, verbose_results, report)
    @test length(ti.testitems) == 1 # the testsetup and only one test item
    @test haskey(setups, :FooSetup)
end

end # `include_testfiles!` testset

@testset "report_empty_testsets" begin
    using ReTestItems: TestItem, report_empty_testsets, PerfStats, ScheduledForEvaluation
    using Test: DefaultTestSet, Fail, Error
    ti = TestItem(Ref(42), "Dummy TestItem", "DummyID", [], false, [], 0, "source/path", 42, ".", nothing)

    ts = DefaultTestSet("Empty testset")
    report_empty_testsets(ti, ts)
    @test_logs (:warn, r"\"Empty testset\"") report_empty_testsets(ti, ts)

    ts = DefaultTestSet("Testset containing an empty testset")
    push!(ts.results, DefaultTestSet("Empty testset"))
    # Only the inner testset is considered empty
    @test_logs (:warn, """
        Test item "Dummy TestItem" at source/path:42 contains test sets without tests:
        "Empty testset"
        """) begin
        report_empty_testsets(ti, ts)
    end

    ts = DefaultTestSet("Testset containing empty testsets")
    push!(ts.results, DefaultTestSet("Empty testset 1"))
    push!(ts.results, DefaultTestSet("Empty testset 2"))
    # Only the inner testsets are considered empty
    @test_logs (:warn, """
        Test item "Dummy TestItem" at source/path:42 contains test sets without tests:
        "Empty testset 1"
        "Empty testset 2"
        """) begin
        report_empty_testsets(ti, ts)
    end

    ts = DefaultTestSet("Testset containing a passing test")
    ts.n_passed = 1
    @test_nowarn report_empty_testsets(ti, ts)

    ts = DefaultTestSet("Testset containing a failed test")
    push!(ts.results, Fail(:test, "false", nothing, false, LineNumberNode(43)));
    @test_nowarn report_empty_testsets(ti, ts)

    ts = DefaultTestSet("Testset that errored")
    push!(ts.results, Error(:test_nonbool, "\"False\"", nothing, nothing, LineNumberNode(43)));
    @test_nowarn report_empty_testsets(ti, ts)
end

@testset "JUnit _error_message" begin
    # Test we cope with the Error/Fail not having file info
    using ReTestItems: _error_message
    line_info = LineNumberNode(42, nothing)
    ti = (; project_root=pkgdir(ReTestItems))  # Don't need a full testitem here
    err = Test.Error(:nontest_error, Expr(:tuple), ErrorException(""), Base.ExceptionStack([]), line_info)
    @test _error_message(err, ti) == "Error during test at unknown:42"
    fail = Test.Fail(:test, Expr(:tuple), "data", "value", line_info)
    @test _error_message(fail, ti) == "Test failed at unknown:42"
end

@testset "_validated_nworker_threads" begin
    auto_cpus = string(Base.Sys.CPU_THREADS)

    @test ReTestItems._validated_nworker_threads(1) == "1"
    @test_throws ArgumentError ReTestItems._validated_nworker_threads(0)
    @test_throws ArgumentError ReTestItems._validated_nworker_threads(-1)

    @test ReTestItems._validated_nworker_threads("1") == "1"
    @test ReTestItems._validated_nworker_threads("auto") == auto_cpus
    @test_throws ArgumentError ReTestItems._validated_nworker_threads("0")
    @test_throws ArgumentError ReTestItems._validated_nworker_threads("-1")
    @test_throws ArgumentError ReTestItems._validated_nworker_threads("1auto")
    @test_throws ArgumentError ReTestItems._validated_nworker_threads("1,")

    if isdefined(Base.Threads, :nthreadpools)
        @test ReTestItems._validated_nworker_threads("1,1") == "1,1"
        @test ReTestItems._validated_nworker_threads("2,1") == "2,1"
        @test ReTestItems._validated_nworker_threads("1,2") == "1,2"
        @test ReTestItems._validated_nworker_threads("auto,1") == "$auto_cpus,1"
        @test ReTestItems._validated_nworker_threads("1,auto") == "1,1"
        @test ReTestItems._validated_nworker_threads("auto,auto") == "$auto_cpus,1"
        @test_throws ArgumentError ReTestItems._validated_nworker_threads("1,-1")
        @test_throws ArgumentError ReTestItems._validated_nworker_threads("0,0")
        @test_throws ArgumentError ReTestItems._validated_nworker_threads("0,1")
        @test_throws ArgumentError ReTestItems._validated_nworker_threads("0,auto")
    end
end

end # internals.jl testset
