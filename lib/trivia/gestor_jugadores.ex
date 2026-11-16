defmodule Trivia.GestorJugadores do
  @moduledoc "Mantiene sesiones activas y monitoriza la vida de sus receptores."
  use GenServer

  def start_link(_argumentos \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def conectar(usuario, clave, receptor, cliente),
    do: GenServer.call(__MODULE__, {:conectar, usuario, clave, receptor, cliente})

  def desconectar(receptor, cliente),
    do: GenServer.call(__MODULE__, {:desconectar, receptor, cliente})

  def usuario(receptor, cliente), do: GenServer.call(__MODULE__, {:usuario, receptor, cliente})

  def init(:ok), do: {:ok, %{por_usuario: %{}, por_receptor: %{}, clientes: %{}, monitores: %{}}}

  def handle_call({:conectar, usuario, clave, receptor, cliente}, _desde, estado) do
    cond do
      not is_pid(receptor) or node(receptor) != node(cliente) ->
        {:reply, {:error, "Receptor inválido para este cliente"}, estado}

      String.trim(usuario) == "" or String.contains?(usuario, " ") or String.trim(clave) == "" ->
        {:reply, {:error, "Usuario o clave inválidos"}, estado}

      String.starts_with?(usuario, "bot_") ->
        {:reply, {:error, "El prefijo bot_ está reservado"}, estado}

      Map.has_key?(estado.por_receptor, receptor) ->
        {:reply, {:error, "Este cliente ya tiene una sesión"}, estado}

      Map.has_key?(estado.por_usuario, usuario) ->
        {:reply, {:error, "Ese usuario ya tiene una sesión abierta"}, estado}

      true ->
        case Trivia.Persistencia.registrar(usuario, clave) do
          {:ok, tipo} ->
            ref = Process.monitor(receptor)

            nuevo = %{
              por_usuario: Map.put(estado.por_usuario, usuario, receptor),
              por_receptor: Map.put(estado.por_receptor, receptor, usuario),
              clientes: Map.put(estado.clientes, receptor, cliente),
              monitores: Map.put(estado.monitores, receptor, ref)
            }

            aviso =
              if tipo == :nuevo, do: "Usuario registrado y conectado", else: "Sesión iniciada"

            {:reply, {:ok, aviso}, nuevo}

          error ->
            {:reply, error, estado}
        end
    end
  end

  def handle_call({:usuario, receptor, cliente}, _desde, estado) do
    case {Map.fetch(estado.por_receptor, receptor), Map.get(estado.clientes, receptor)} do
      {{:ok, usuario}, ^cliente} -> {:reply, {:ok, usuario}, estado}
      _ -> {:reply, {:error, "Debes iniciar sesión desde este cliente"}, estado}
    end
  end

  def handle_call({:desconectar, receptor, cliente}, _desde, estado) do
    case {Map.fetch(estado.por_receptor, receptor), Map.get(estado.clientes, receptor)} do
      {{:ok, usuario}, ^cliente} ->
        GenServer.cast(Trivia.GestorPartidas, {:abandonar, usuario})
        {:reply, {:ok, "Sesión cerrada"}, quitar_sesion(estado, receptor)}

      _ ->
        {:reply, {:error, "No existe sesión activa para este cliente"}, estado}
    end
  end

  def handle_info({:DOWN, ref, :process, receptor, _motivo}, estado) do
    case Map.fetch(estado.monitores, receptor) do
      {:ok, ^ref} ->
        usuario = Map.fetch!(estado.por_receptor, receptor)
        GenServer.cast(Trivia.GestorPartidas, {:abandonar, usuario})
        {:noreply, quitar_sesion(estado, receptor)}

      _ ->
        {:noreply, estado}
    end
  end

  defp quitar_sesion(estado, receptor) do
    usuario = Map.get(estado.por_receptor, receptor)
    ref = Map.get(estado.monitores, receptor)
    if ref != nil, do: Process.demonitor(ref, [:flush])

    %{
      estado
      | por_usuario: Map.delete(estado.por_usuario, usuario),
        por_receptor: Map.delete(estado.por_receptor, receptor),
        clientes: Map.delete(estado.clientes, receptor),
        monitores: Map.delete(estado.monitores, receptor)
    }
  end
end
