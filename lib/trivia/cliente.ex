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
end
