defmodule KV.Registry do
  use GenServer

  ## Client API

 @doc """
 Starts the registry.
 """
 def start_link(opts) do
   GenServer.start_link(__MODULE__, :ok, opts)
 end

 @doc """
 Looks up the bucket pid for `name` stored in `server`.

 Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
 """
 def lookup(server, name) do
   GenServer.call(server, {:lookup, name})
 end

 @doc """
 Ensures there is a bucket associated with the given `name` in `server`.
 """
 def create(server, name) do
   GenServer.cast(server, {:create, name})
 end

  ## Defining GenServer Callbacks

 @impl true
 def init(:ok) do
   names = %{}
   refs = %{}
   {:ok, {names, refs}}
 end

 def gossip_full(numNodes) do
   for i <- 1..numNodes do
     GenServer.cast(KV.Registry,{:create,i})
   end
 end

 def push_sum_full(numNodes) do
   for i <- 1..numNodes do
     GenServer.call(KV.Registry,{:create_push_full,i})
   end
   #initialize
   state = GenServer.call(KV.Registry, {:getState})
   if (state !=%{}) do
     {_,random_pid} = Enum.random(state)
     Task.await(Task.async(fn->GenServer.cast(random_pid,{:transrumor,{0,0}}) end),:infinity)
   end
 end

 @impl true
 def handle_call({:lookup, name}, _from, state) do
   {names, _} = state
   {:reply, Map.fetch(names, name), state}
 end

 @impl true
 def handle_call({:getState}, _from, state) do
   {:reply, elem(state, 0), state}
 end

  @impl true
  def handle_cast({:create, name}, {names, refs}) do
    if Map.has_key?(names, name) do
      {:noreply, {names, refs}}
    else
      {:ok, pid} = DynamicSupervisor.start_child(KV.BucketSupervisor, {KV.Bucket,0})
      ref = Process.monitor(pid)
      refs = Map.put(refs, ref, name)
      names = Map.put(names, name, pid)
      {:noreply, {names, refs}}
    end
  end

  @impl true
  def handle_call({:create_push_full, name},_from, {names, refs}) do
    if Map.has_key?(names, name) do
      #{:noreply, {names, refs}}
      {:reply,{names, refs}, {names, refs}}
    else
      {:ok, pid} = DynamicSupervisor.start_child(KV.BucketSupervisor, {KV.Bucket2,[name,1]})
      ref = Process.monitor(pid)
      refs = Map.put(refs, ref, name)
      names = Map.put(names, name, pid)
      #{:noreply, {names, refs}}
      IO.inspect(pid)
      {:reply, {names, refs},{names, refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    # handle failure according to the reason
    #IO.puts("killed")
    {name, refs} = Map.pop(refs, ref)
    names = Map.delete(names, name)
    {:noreply, {names, refs}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

end
