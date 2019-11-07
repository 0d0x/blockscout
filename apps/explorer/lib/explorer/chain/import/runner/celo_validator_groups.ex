defmodule Explorer.Chain.Import.Runner.CeloValidatorGroups do
    @moduledoc """
    Bulk imports Celo validator groups to the DB table.
    """
  
    require Ecto.Query
  
    alias Ecto.{Changeset, Multi, Repo}
    alias Explorer.Chain.{Import, CeloValidatorGroup}
  
    import Ecto.Query, only: [from: 2]
  
    @behaviour Import.Runner
  
    # milliseconds
    @timeout 60_000
  
    @type imported :: [CeloValidatorGroup.t()]
  
    @impl Import.Runner
    def ecto_schema_module, do: CeloValidatorGroup
  
    @impl Import.Runner
    def option_key, do: :celo_validator_groups
  
    @impl Import.Runner
    def imported_table_row do
      %{
        value_type: "[#{ecto_schema_module()}.t()]",
        value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
      }
    end
  
    @impl Import.Runner
    def run(multi, changes_list, %{timestamps: timestamps} = options) do
      insert_options =
        options
        |> Map.get(option_key(), %{})
        |> Map.take(~w(on_conflict timeout)a)
        |> Map.put_new(:timeout, @timeout)
        |> Map.put(:timestamps, timestamps)
  
      # Enforce ShareLocks tables order (see docs: sharelocks.md)
      multi
      |> Multi.run(:acquire_all_items, fn repo, _ ->
        acquire_all_items(repo)
      end)
      |> Multi.run(:insert_items, fn repo, _ ->
        insert(repo, changes_list, insert_options)
      end)
    end
  
    @impl Import.Runner
    def timeout, do: @timeout
  
    defp acquire_all_items(repo) do
      query =
        from(
          account in CeloValidatorGroup,
          # Enforce ShareLocks order (see docs: sharelocks.md)
          order_by: account.address,
          lock: "FOR UPDATE"
        )
  
      accounts = repo.all(query)
  
      {:ok, accounts}
    end
  
    @spec insert(Repo.t(), [map()], %{
            optional(:on_conflict) => Import.Runner.on_conflict(),
            required(:timeout) => timeout,
            required(:timestamps) => Import.timestamps()
          }) ::
            {:ok, [CeloValidatorGroup.t()]}
            | {:error, [Changeset.t()]}
    defp insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
      on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)
  
      # Enforce ShareLocks order (see docs: sharelocks.md)
      ordered_changes_list = Enum.sort_by(changes_list, & &1.address)
      uniq_changes_list = Enum.dedup_by(ordered_changes_list, & &1.address)

      {:ok, _} =
        Import.insert_changes_list(
          repo,
          uniq_changes_list,
          conflict_target: :address,
          on_conflict: on_conflict,
          for: CeloValidatorGroup,
          returning: [:address],
          timeout: timeout,
          timestamps: timestamps
        )
    end
  
    defp default_on_conflict do
      from(
        account in CeloValidatorGroup,
        update: [
          set: [
            commission: fragment("EXCLUDED.commission"),
            
            inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", account.inserted_at),
            updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", account.updated_at)
          ]
        ]
      )
    end
  
  end
  