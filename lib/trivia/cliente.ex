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

  defp interpretar(""), do: {:local, ""}
  defp interpretar("help"), do: {:local, ayuda()}
  defp interpretar("disconnect"), do: :disconnect
  defp interpretar("score"), do: :score
  defp interpretar("ranking"), do: {:ranking, nil}
  defp interpretar("start_game"), do: :start_game
  defp interpretar("leave_game"), do: :leave_game

  defp interpretar(comando) do
    case String.split(comando, " ", trim: true) do
      ["connect", usuario, clave] -> {:connect, usuario, clave}
      ["ranking", tema] -> {:ranking, tema}
      ["add_bot", dificultad] -> {:add_bot, dificultad}
      ["answer", letra] -> {:answer, String.upcase(letra)}
      ["lifeline", tipo] when tipo in ["5050", "doble"] -> {:lifeline, tipo}
      ["lifeline" | _] -> {:error, "Usa lifeline 5050 o lifeline doble"}
      ["create_game" | parametros] -> parametros_partida(parametros)
      _ -> {:error, "Comando inválido. Escribe help"}
    end
  end

  defp parametros_partida(parametros) do
    opciones =
      Enum.reduce(parametros, %{}, fn parametro, mapa ->
        case String.split(parametro, "=", parts: 2) do
          [clave, valor] -> Map.put(mapa, clave, valor)
          _ -> mapa
        end
      end)

    with tema when is_binary(tema) and tema != "" <- Map.get(opciones, "tema"),
         {cantidad, ""} <- Integer.parse(Map.get(opciones, "preguntas", "")),
         {tiempo, ""} <- Integer.parse(Map.get(opciones, "tiempo", "")) do
      {:create_game, tema, cantidad, tiempo}
    else
      _ -> {:error, "Formato: create_game tema=ciencia preguntas=5 tiempo=15"}
    end
  end

  defp ayuda do
    """
    Comandos:
      connect <usuario> <clave>
      disconnect
      create_game tema=<tema> preguntas=<n> tiempo=<segundos>
      add_bot facil
      add_bot dificil
      start_game
      answer A | B | C | D
      lifeline 5050  (dos opciones; sin bono de rapidez)
      lifeline doble (duplica puntos positivos o negativos)
      leave_game
      score
      ranking [tema]
      help
      salir
    """
  end
end
