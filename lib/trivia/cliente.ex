defmodule Trivia.Cliente do
  @moduledoc "Interfaz de consola sin datos ni lógica de juego en el cliente."

  def iniciar do
    if node() == :nonode@nohost do
      IO.puts("Debes iniciar IEx con --sname, por ejemplo: iex --sname pedro -S mix")
    else
      receptor = Trivia.Receptor.iniciar()
      IO.puts("Trivia Concurrente. Escribe help para ver los comandos.")
      leer(receptor)
    end
  end

  defp leer(receptor) do
    case IO.gets("trivia> ") do
      :eof ->
        cerrar(receptor)

      {:error, _} ->
        cerrar(receptor)

      linea ->
        comando = String.trim(linea)

        if comando in ["salir", "exit", "quit"] do
          solicitar(receptor, :disconnect)
          cerrar(receptor)
        else
          case interpretar(comando) do
            {:local, texto} -> IO.puts(texto)
            {:error, texto} -> IO.puts("ERROR: #{texto}")
            solicitud -> solicitar(receptor, solicitud)
          end

          leer(receptor)
        end
    end
  end

  defp cerrar(receptor) do
    send(receptor, :detener)
    :ok
  end

  defp solicitar(receptor, solicitud) do
    solicitud =
      case solicitud do
        {:lifeline, tipo} -> {:lifeline, tipo, ronda_actual(receptor)}
        otra -> otra
      end

    nombre_local = Atom.to_string(node())
    host = nombre_local |> String.split("@") |> List.last()
    servidor = String.to_atom("servidor@" <> host)

    if Node.connect(servidor) do
      try do
        case GenServer.call(
               {Trivia.Servidor, servidor},
               {:solicitar, receptor, solicitud},
               15_000
             ) do
          {:ok, texto} ->
            if not match?({:lifeline, "5050", _}, solicitud), do: IO.puts(texto)

          {:error, texto} ->
            IO.puts("ERROR: #{texto}")

          otro ->
            IO.inspect(otro)
        end
      catch
        :exit, _ -> IO.puts("ERROR: el servidor no responde")
      end
    else
      IO.puts("ERROR: servidor no disponible (verifica el nodo y la cookie)")
    end
  end

  defp ronda_actual(receptor) do
    referencia = make_ref()
    send(receptor, {:ronda_actual, self(), referencia})

    receive do
      {^referencia, token} -> token
    after
      1000 -> nil
    end
  end
end
