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

  def handle_cast({:abandonar, usuario}, estado) do
    case Map.fetch(estado.por_usuario, usuario) do
      {:ok, id} ->
        meta = Map.fetch!(estado.partidas, id)

        if Process.alive?(meta.pid) do
          try do
            Trivia.Partida.abandonar(meta.pid)
          catch
            :exit, _ -> :ok
          end
        end

        {:noreply, estado}

      :error ->
        {:noreply, estado}
    end
  end

  def handle_cast({:registrar_partida, id, pid}, estado) do
    case Map.fetch(estado.partidas, id) do
      {:ok, meta} when meta.pid != pid ->
        send(
          meta.receptor,
          {:trivia, :aviso,
           "La partida #{id} falló y se reinició desde cero. Agrega los bots e inicia nuevamente."}
        )

        partidas = Map.put(estado.partidas, id, %{meta | pid: pid})
        {:noreply, %{estado | partidas: partidas}}

      _ ->
        {:noreply, estado}
    end
  end

  def handle_cast({:terminada, id}, estado) do
    case Map.pop(estado.partidas, id) do
      {nil, _} ->
        {:noreply, estado}

      {meta, nuevas_partidas} ->
        DynamicSupervisor.terminate_child(Trivia.SupervisorPartidas, meta.pid)

        {:noreply,
         %{
           estado
           | partidas: nuevas_partidas,
             por_usuario: Map.delete(estado.por_usuario, meta.creador)
         }}
    end
  end

  defp iniciar_partida(estado, usuario, receptor, tema, nivel, cantidad, tiempo) do
    case Trivia.Persistencia.siguiente_id() do
      {:ok, id} ->
        opciones = [
          id: id,
          creador: usuario,
          receptor: receptor,
          tema: tema,
          nivel: nivel,
          total: cantidad,
          tiempo: tiempo,
          gestor: self()
        ]

        case DynamicSupervisor.start_child(Trivia.SupervisorPartidas, {Trivia.Partida, opciones}) do
          {:ok, pid} ->
            meta = %{pid: pid, creador: usuario, receptor: receptor}

            nuevo = %{
              estado
              | partidas: Map.put(estado.partidas, id, meta),
                por_usuario: Map.put(estado.por_usuario, usuario, id)
            }

            {:reply, {:ok, "Creada #{id} (#{tema}, nivel #{nivel}). Agrega 2 o 3 bots."}, nuevo}

          {:error, motivo} ->
            {:reply, {:error, "No se pudo iniciar la partida: #{inspect(motivo)}"}, estado}
        end

      error ->
        {:reply, error, estado}
    end
  end

  defp con_partida(estado, usuario, funcion) do
    case Map.fetch(estado.por_usuario, usuario) do
      {:ok, id} ->
        pid = estado.partidas |> Map.fetch!(id) |> Map.fetch!(:pid)

        if Process.alive?(pid) do
          try do
            {:reply, funcion.(pid), estado}
          catch
            :exit, _ ->
              {:reply, {:error, "La partida está reiniciándose; intenta nuevamente"}, estado}
          end
        else
          {:reply, {:error, "La partida está reiniciándose; intenta nuevamente"}, estado}
        end

      :error ->
        {:reply, {:error, "No estás en ninguna partida"}, estado}
    end
  end
end
