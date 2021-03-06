defmodule SafeMachine do

  @doc false
  defmacro __using__(_opts) do
    quote do
      require Logger
      import SafeMachine
      Module.put_attribute(__MODULE__, :state_transitions, %{})
      @on_definition SafeMachine
    end
  end

  @doc false
  defmacro safe_machine_finish do
    quote do
      # FIXME: replace this with an after_compile type check for transition consistency
      # but we still want this at runtime :(
      def get_state_transitions do
        @state_transitions
      end

      # Recusively do a transition until done
      def fully_transition(%__MODULE__{state: start} = obj) do
        if to_state = get_state_transitions()[start] do
          a = do_transition(obj, start, to_state)
          IO.inspect(obj)
          IO.inspect(start)
          IO.inspect(to_state)
          IO.inspect(a)
          case a do
            {:ok, obj} -> fully_transition(obj)
            {:error, err} -> {:error, err, obj}
          end
        else
          {:ok, obj}
        end
      end
    end
  end

  @doc false
  def __on_definition__(_env, :def, :do_transition, args, _guards, _body) do
    {:=, _, [from_state | _]} = Enum.at(args, 1)
    {:=, _, [to_state | _]} = Enum.at(args, 2)
    IO.puts "Defining transition from #{from_state} to #{to_state}."
    # FIXME: do static analysis here of any circular transitions
  end

  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    # Serves as a catchall for on_definition
  end

  @doc false
  defmacro deftransition({:=, _, [{:%, _, [struct_name, {:%{}, _, struct_args}]}, struct_self]}, [to: to], clause \\ []) do
    # IO.inspect(Enum.map(Keyword.get_values(clause, :rescue), fn v -> {:rescue, v} end))
    # IO.inspect(Code.compile_string("rescue e in RunetimeError -> e"))
    from = if Keyword.keyword?(struct_args) && struct_args[:state] do
      struct_args[:state]
    else
      raise "\"state:\" not provided in expansion"
    end

    quote do
      Module.put_attribute(__MODULE__, :state_transitions, Map.put(Module.get_attribute(__MODULE__, :state_transitions), unquote(from), unquote(to))) # we can't include unquote(struct_args) due to unbound variables

      # FIXME: handle when gaurds
      def do_transition(%unquote(struct_name){unquote_splicing(struct_args)} = unquote(struct_self), unquote(from) = from, unquote(to) = to) do
        Logger.debug("TRANSITION MACRO: do_transition " <> Atom.to_string(from) <> " ~> " <> Atom.to_string(to))
        Logger.debug("SELF:  " <> inspect(unquote(struct_self)))
        result = try do
          transition_outcome = unquote(clause[:do])
          Logger.debug("DO FINISHED")
          case transition_outcome do
            %unquote(struct_name){state: unquote(from)} = result -> %{result | state: to}
            %unquote(struct_name){state: unexpected_state} -> raise "Did not expect change of :state during #{__MODULE__}.do_transition from :#{unquote(from)} to :#{unquote(to)}: got %#{unquote(struct_name)}{state: #{unexpected_state}}"
            _ -> %{unquote(struct_self) | state: to}
          end
        catch
          # FIXME: how to handle catch with default x -> x
          # unquote(clause[:catch])
          x -> x
        after
          # FIXME: properly handle clause and defaulted, or whether to allow after
          # unquote(clause[:after])
          Logger.debug("AFTER FINISHED")
        end
        Logger.debug("TRANSITION MACRO: end " <> Atom.to_string(from) <> " ~> " <> Atom.to_string(to))
        case result do
          %unquote(struct_name){state: to} = unquote(struct_self) -> {:ok, unquote(struct_self)}
          _ -> {:error, result}
        end
      end
    end
  end

  defmacro unsafe(do: do_clause) do
    quote do
      unquote(do_clause)
    end
  end

end
