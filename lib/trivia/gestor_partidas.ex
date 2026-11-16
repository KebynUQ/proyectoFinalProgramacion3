defmodule Trivia.GestorPartidas do
  @moduledoc "Asocia cada usuario con su proceso de partida y gestiona los reinicios."
  use GenServer

  def start_link(_argumentos \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def crear(usuario, receptor, tema, cantidad, tiempo),
    do: GenServer.call(__MODULE__, {:crear, usuario, receptor, tema, cantidad, tiempo})

  def agregar_bot(usuario, dificultad),
    do: GenServer.call(__MODULE__, {:agregar_bot, usuario, dificultad})

  def comenzar(usuario), do: GenServer.call(__MODULE__, {:comenzar, usuario})
  def responder(usuario, letra), do: GenServer.call(__MODULE__, {:responder, usuario, letra})

  def usar_comodin(usuario, tipo, token),
    do: GenServer.call(__MODULE__, {:comodin, usuario, tipo, token})

  def abandonar(usuario), do: GenServer.call(__MODULE__, {:abandonar, usuario})

  def init(:ok), do: {:ok, %{partidas: %{}, por_usuario: %{}}}

  def handle_call({:crear, usuario, receptor, tema, cantidad, tiempo}, _desde, estado) do
    cond do
      Map.has_key?(estado.por_usuario, usuario) ->
        {:reply, {:error, "Ya estás en una partida"}, estado}

      not is_integer(cantidad) or cantidad < 1 or cantidad > 10 ->
        {:reply, {:error, "La cantidad de preguntas debe estar entre 1 y 10"}, estado}

      not is_integer(tiempo) or tiempo < 1 ->
        {:reply, {:error, "El tiempo por pregunta debe ser positivo"}, estado}

      true ->
        case Trivia.Persistencia.historial() do
          {:ok, historial} ->
            nivel = Trivia.Nivel.nivel_usuario(historial, usuario, tema)

            case Trivia.BancoPreguntas.disponibles?(tema, nivel, cantidad) do
              :ok -> iniciar_partida(estado, usuario, receptor, tema, nivel, cantidad, tiempo)
              error -> {:reply, error, estado}
            end

          error ->
            {:reply, error, estado}
        end
    end
  end

  def handle_call({:agregar_bot, usuario, dificultad}, _desde, estado) do
    con_partida(estado, usuario, fn pid -> Trivia.Partida.agregar_bot(pid, dificultad) end)
  end

  def handle_call({:comenzar, usuario}, _desde, estado) do
    con_partida(estado, usuario, fn pid -> Trivia.Partida.comenzar(pid) end)
  end

  def handle_call({:responder, usuario, letra}, _desde, estado) do
    con_partida(estado, usuario, fn pid -> Trivia.Partida.responder(pid, usuario, letra) end)
  end

  def handle_call({:comodin, usuario, tipo, token}, _desde, estado) do
    con_partida(estado, usuario, fn pid ->
      Trivia.Partida.usar_comodin(pid, usuario, tipo, token)
    end)
  end

  def handle_call({:abandonar, usuario}, _desde, estado) do
    con_partida(estado, usuario, fn pid -> Trivia.Partida.abandonar(pid) end)
  end
end
