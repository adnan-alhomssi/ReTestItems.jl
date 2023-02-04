"""
    TestSetupModules()

A set of test setups.
Used to keep track of which test setups have been evaluated on a given process.
"""
struct TestSetupModules
    lock::ReentrantLock
    modules::Dict{Symbol, Module} # set of @testsetup modules that have already been evaled
end

TestSetupModules() = TestSetupModules(ReentrantLock(), Dict{Symbol, Module}())

getmodule(f, ss::TestSetupModules, key::Symbol) = @lock ss.lock get!(f, ss.modules, key)

struct TestSetups
    lock::ReentrantLock
    setups::Dict{String, Channel{TestSetup}} # Channel of size 1 that is `put!`, but never `take!`-en, only `fetch`-ed, so a "Future"
end

TestSetups() = TestSetups(ReentrantLock(), Dict{String, Channel{TestSetup}}())

function Base.getindex(ss::TestSetups, key::String)
    # we need to be careful here that the lock is only used for getting the desired
    # test setup *channel*, but not for the `fetch` operation; otherwise, we would
    # be deadlocked w/ a task holding the lock waiting on `fetch`, but the `put!`
    # would be locked trying to get the ss.lock
    ch = @lock ss.lock get!(() -> Channel{TestSetup}(1), ss.setups, key)
    @debugv 1 "fetching test setup $key"
    x = fetch(ch)
    @debugv 1 "fetched test setup $key"
    return x
end

function Base.setindex!(ss::TestSetups, val::TestSetup, key::String)
    # same care w/ the lock as above
    ch = @lock ss.lock get!(() -> Channel{TestSetup}(1), ss.setups, key)
    # assertion that we are only ever putting a single value into the channel
    @assert !isready(ch)
    @debugv 1 "putting test setup $key"
    put!(ch, val)
    return val
end

"""
    TestContext()

A context for test setups. Used to keep track of
`@testsetup`-expanded `TestSetup`s and a `TestSetupModules`
for a given process; used in `runtestitem` to ensure
any setups relied upon by the `@testitem` are evaluated
on the process that will run the test item.
"""
mutable struct TestContext
    # name of overall project we're eval-ing in
    projectname::String
    # name => quote'd code
    setups_quoted::TestSetups
    # name => eval'd code
    setups_evaled::TestSetupModules

    # user of TestContext must create and set the
    # TestSetupModules explicitly, since they must be process-local
    # and shouldn't be serialized across processes
    TestContext(name) = new(name, TestSetups())
end

# FilteredChannel applies a filtering function `f` to items
# when you try to `put!` and only puts if `f` returns true.
struct FilteredChannel{F, T}
    f::F
    ch::T
end

Base.put!(ch::FilteredChannel, x) = ch.f(x) && put!(ch.ch, x)
Base.take!(ch::FilteredChannel) = take!(ch.ch)
Base.close(ch::FilteredChannel) = close(ch.ch)
Base.close(ch::FilteredChannel, e::Exception) = close(ch.ch, e)
Base.isopen(ch::FilteredChannel) = isopen(ch.ch)

chan(ch::RemoteChannel) = channel_from_id(remoteref_id(ch))
