defmodule Trivia.Servidor do
  @moduledoc "Punto único de entrada: valida la sesión y enruta solicitudes del cliente."
  use GenServer

  def start_link(_argumentos \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def init(:ok), do: {:ok, %{}}

  def handle_call({:solicitar, receptor, solicitud}, {cliente, _referencia}, estado) do
    {:reply, ejecutar(receptor, cliente, solicitud), estado}
  end

  defp ejecutar(receptor, cliente, {:connect, usuario, clave}) do
    Trivia.GestorJugadores.conectar(usuario, clave, receptor, cliente)
  end

  defp ejecutar(receptor, cliente, solicitud) do
    case Trivia.GestorJugadores.usuario(receptor, cliente) do
      {:ok, usuario} -> ejecutar_autenticado(usuario, receptor, cliente, solicitud)
      error -> error
    end
  end

  defp ejecutar_autenticado(_usuario, receptor, cliente, :disconnect) do
    Trivia.GestorJugadores.desconectar(receptor, cliente)
  end

  defp ejecutar_autenticado(usuario, receptor, _cliente, {:create_game, tema, cantidad, tiempo}) do
    Trivia.GestorPartidas.crear(usuario, receptor, tema, cantidad, tiempo)
  end

  defp ejecutar_autenticado(usuario, _receptor, _cliente, {:add_bot, dificultad}) do
    Trivia.GestorPartidas.agregar_bot(usuario, dificultad)
  end

  defp ejecutar_autenticado(usuario, _receptor, _cliente, :start_game) do
    Trivia.GestorPartidas.comenzar(usuario)
  end

  defp ejecutar_autenticado(usuario, _receptor, _cliente, :leave_game) do
    Trivia.GestorPartidas.abandonar(usuario)
  end

  defp ejecutar_autenticado(usuario, _receptor, _cliente, {:answer, letra}) do
    Trivia.GestorPartidas.responder(usuario, letra)
  end

  defp ejecutar_autenticado(usuario, _receptor, _cliente, {:lifeline, tipo, token}) do
    Trivia.GestorPartidas.usar_comodin(usuario, tipo, token)
  end

  defp ejecutar_autenticado(usuario, _receptor, _cliente, :score) do
    case Trivia.Persistencia.historial() do
      {:ok, historial} ->
        datos = Trivia.Nivel.estadisticas(historial, usuario)

        filas =
          datos.temas
          |> Enum.sort_by(fn {tema, _puntos} -> tema end)
          |> Enum.map(fn {tema, puntos} ->
            "#{tema}: #{puntos} puntos (#{Trivia.Nivel.desde_puntos(puntos)})"
          end)

        texto =
          [
            "=== #{usuario} ===",
            "Puntaje acumulado: #{datos.puntaje}",
            "Partidas jugadas: #{datos.partidas}" | filas
          ]
          |> Enum.join("\n")

        {:ok, texto}

      error ->
        error
    end
  end

  defp ejecutar_autenticado(_usuario, _receptor, _cliente, {:ranking, tema}) do
    case Trivia.Persistencia.historial() do
      {:ok, historial} ->
        filas = Trivia.Nivel.ranking(historial, tema)
        titulo = if tema == nil, do: "=== Ranking global ===", else: "=== Ranking #{tema} ==="

        detalles =
          filas
          |> Enum.with_index(1)
          |> Enum.map(fn {{usuario, datos}, puesto} ->
            "#{puesto}. #{usuario}: #{datos.puntaje} puntos, #{datos.partidas} partidas"
          end)

        {:ok, Enum.join([titulo | detalles], "\n")}

      error ->
        error
    end
  end

  defp ejecutar_autenticado(_usuario, _receptor, _cliente, _otro),
    do: {:error, "Comando no reconocido"}
end
