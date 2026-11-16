defmodule Trivia.Partida do
  @moduledoc "Una partida independiente, supervisada, con rondas, respuestas y bots."
  use GenServer, restart: :transient

  def start_link(opciones), do: GenServer.start_link(__MODULE__, opciones)
  def agregar_bot(pid, dificultad), do: GenServer.call(pid, {:agregar_bot, dificultad})
  def comenzar(pid), do: GenServer.call(pid, :comenzar)
  def responder(pid, usuario, letra, token \\ nil),
    do: GenServer.call(pid, {:responder, usuario, letra, token})
  def usar_comodin(pid, usuario, tipo, token),
    do: GenServer.call(pid, {:comodin, usuario, tipo, token})
  def abandonar(pid), do: GenServer.call(pid, :abandonar)

  def opciones_5050(opciones, correcta) do
    incorrectas = Enum.filter(["A", "B", "C", "D"], fn letra -> letra != correcta end)
    otra = Enum.random(incorrectas)
    %{correcta => Map.fetch!(opciones, correcta), otra => Map.fetch!(opciones, otra)}
  end
   def validar_agregar_bot(estado, cantidad) do
    cond do
      estado != :esperando -> {:error, "La partida ya está iniciada o terminó"}
      cantidad >= 3 -> {:error, "La partida está llena"}
      true -> :ok
    end
  end

  def validar_comienzo(estado, cantidad) do
    cond do
      estado != :esperando -> {:error, "La partida no está esperando"}
      cantidad < 2 -> {:error, "Debes agregar al menos dos bots"}
      true -> :ok
    end
  end

  # Validación pura para que pueda probarse sin iniciar procesos.
  def validar_respuesta(estado, usuario, letra) do
    cond do
      estado.estado != :en_curso or not estado.ronda_abierta ->
        {:error, "No hay ninguna ronda abierta"}

      letra not in ["A", "B", "C", "D"] ->
        {:error, "Solo puedes responder A, B, C o D"}

      Map.has_key?(estado.respuestas, usuario) ->
        {:error, "Ya respondiste esta ronda"}

      true -> :ok
    end
  end

  def init(opciones) do
    gestor = Keyword.fetch!(opciones, :gestor)
    id = Keyword.fetch!(opciones, :id)
    creador = Keyword.fetch!(opciones, :creador)
    GenServer.cast(gestor, {:registrar_partida, id, self()})

    {:ok, %{
      id: id,
      creador: creador,
      tema: Keyword.fetch!(opciones, :tema),
      nivel: Keyword.fetch!(opciones, :nivel),
      total: Keyword.fetch!(opciones, :total),
      tiempo_ms: Keyword.fetch!(opciones, :tiempo) * 1000,
      receptor: Keyword.fetch!(opciones, :receptor),
      gestor: gestor,
      bots: [],
      estado: :esperando,
      ronda_abierta: false,
      preguntas: [],
      indice: 0,
      respuestas: %{},
      puntajes: %{creador => 0},
      inicio_ms: 0,
      timer: nil,
      token: 0,
      resultado_guardado: false,
      uso_5050: false,
      uso_doble: false,
      ronda_5050: false,
      ronda_doble: false,
      opciones_ronda_5050: nil
    }}
  end

  def handle_call({:agregar_bot, dificultad}, _desde, estado) do
    with true <- dificultad in ["facil", "dificil"],
         :ok <- validar_agregar_bot(estado.estado, length(estado.bots)) do
      numero = length(estado.bots) + 1
      nombre = "bot_#{numero}"
      pid = Trivia.Bot.iniciar(nombre, dificultad)
      bot = %{nombre: nombre, pid: pid, dificultad: dificultad}
      nuevo = %{estado |
        bots: estado.bots ++ [bot],
        puntajes: Map.put(estado.puntajes, nombre, 0)
      }
      {:reply, {:ok, "Agregado #{nombre} (#{dificultad})"}, nuevo}
    else
      false -> {:reply, {:error, "Dificultad inválida (facil o dificil)"}, estado}
      error -> {:reply, error, estado}
    end
  end

  def handle_call(:comenzar, _desde, estado) do
    case validar_comienzo(estado.estado, length(estado.bots)) do
      :ok ->
        case Trivia.BancoPreguntas.seleccionar(estado.tema, estado.nivel, estado.total) do
          {:ok, preguntas} ->
            send(self(), :abrir_ronda)
            {:reply, {:ok, "La partida #{estado.id} está comenzando. Tienes lifeline 5050 y lifeline doble, una vez cada uno."},
              %{estado | preguntas: preguntas, estado: :en_curso}}

          error -> {:reply, error, estado}
        end

      error -> {:reply, error, estado}
    end
  end

  def handle_call({:responder, usuario, letra, token}, _desde, estado) do
    es_humano = usuario == estado.creador and token == nil
    es_bot = token == estado.token and
      Enum.any?(estado.bots, fn bot -> bot.nombre == usuario end)

    if es_humano or es_bot do
      {nuevo, respuesta} = registrar_respuesta(estado, usuario, letra)
      {:reply, respuesta, nuevo}
    else
      {:reply, {:error, "Este jugador no pertenece a la partida o la ronda es antigua"}, estado}
    end
  end

  def handle_call({:comodin, usuario, tipo, token}, _desde, estado) do
    cond do
      usuario != estado.creador ->
        {:reply, {:error, "Solo el jugador humano puede utilizar comodines"}, estado}

      tipo not in ["5050", "doble"] ->
        {:reply, {:error, "Comodín inválido. Usa lifeline 5050 o lifeline doble"}, estado}

      estado.estado != :en_curso or not estado.ronda_abierta ->
        {:reply, {:error, "Solo puedes utilizar comodines durante una ronda abierta"}, estado}

      token != estado.token ->
        {:reply, {:error, "La ronda cambió; solicita el comodín en la pregunta actual"}, estado}

      tiempo_restante(estado) == 0 ->
        {:reply, {:error, "El tiempo de la pregunta se agotó"}, estado}

      Map.has_key?(estado.respuestas, usuario) ->
        {:reply, {:error, "No puedes utilizar un comodín después de responder"}, estado}

      tipo == "5050" and estado.uso_5050 ->
        {:reply, {:error, "Ya utilizaste el comodín 50/50 en esta partida"}, estado}

      tipo == "doble" and estado.uso_doble ->
        {:reply, {:error, "Ya utilizaste el comodín Doble en esta partida"}, estado}

      tipo == "5050" ->
        pregunta = Enum.at(estado.preguntas, estado.indice)
        opciones = opciones_5050(pregunta["opciones"], pregunta["respuesta"])
        enviar(estado.receptor, :pregunta_5050, %{
          partida_id: estado.id,
          numero: estado.indice + 1,
          total: estado.total,
          tema: estado.tema,
          nivel: pregunta["nivel"],
          enunciado: pregunta["enunciado"],
          opciones: opciones,
          tiempo_restante_ms: tiempo_restante(estado),
          token: estado.token
        })
        nuevo = %{estado | uso_5050: true, ronda_5050: true, opciones_ronda_5050: opciones}
        {:reply, {:ok, "Comodín 50/50 utilizado. La bonificación por rapidez será 0 en esta ronda"}, nuevo}

      true ->
        nuevo = %{estado | uso_doble: true, ronda_doble: true}
        {:reply, {:ok, "Comodín Doble activado: tus puntos de esta ronda se multiplicarán por dos"}, nuevo}
    end
  end

  def handle_call(:abandonar, _desde, estado) do
    case estado.estado do
      :esperando ->
        send(self(), :cancelar_partida)
        {:reply, {:ok, "Partida cancelada"}, %{estado | estado: :finalizada}}

      :en_curso ->
        send(self(), :terminar_partida)
        {:reply, {:ok, "Partida abandonada; se guardará el puntaje acumulado"},
          %{estado | estado: :finalizada, ronda_abierta: false}}

      :finalizada -> {:reply, {:ok, "La partida ya terminó"}, estado}
    end
  end

  def handle_info(:abrir_ronda, %{estado: :en_curso, ronda_abierta: false} = estado) do
    pregunta = Enum.at(estado.preguntas, estado.indice)
    token = estado.token + 1
    inicio = System.monotonic_time(:millisecond)
    tiempo_seg = div(estado.tiempo_ms, 1000)

    mensaje = %{
      partida_id: estado.id,
      numero: estado.indice + 1,
      total: estado.total,
      tema: estado.tema,
      nivel: pregunta["nivel"],
      enunciado: pregunta["enunciado"],
      opciones: pregunta["opciones"],
      tiempo: tiempo_seg,
      token: token
    }

    # Humanos y bots reciben la misma notificación de pregunta.
    # La respuesta correcta solo se añade al mensaje de los bots del servidor.
    enviar(estado.receptor, :pregunta, mensaje)

    mensaje_bot = Map.merge(mensaje, %{
      partida: self(),
      token: token,
      respuesta: pregunta["respuesta"],
      tiempo_ms: estado.tiempo_ms
    })
    Enum.each(estado.bots, fn bot ->
      enviar(bot.pid, :pregunta, mensaje_bot)
    end)

    timer = Process.send_after(self(), {:cerrar_por_tiempo, token}, estado.tiempo_ms)
    {:noreply, %{estado |
      ronda_abierta: true, inicio_ms: inicio, respuestas: %{}, timer: timer, token: token,
      ronda_5050: false, ronda_doble: false, opciones_ronda_5050: nil}}
  end

  def handle_info(:abrir_ronda, estado), do: {:noreply, estado}

  def handle_info({:cerrar_por_tiempo, token}, estado) do
    if estado.ronda_abierta and token == estado.token do
      {:noreply, cerrar_ronda(estado)}
    else
      {:noreply, estado}
    end
  end

  def handle_info(:siguiente_ronda, %{estado: :en_curso, ronda_abierta: false} = estado) do
    send(self(), :abrir_ronda)
    {:noreply, estado}
  end

  def handle_info(:siguiente_ronda, estado), do: {:noreply, estado}

  def handle_info(:cancelar_partida, estado) do
    enviar_todos(estado, :aviso, "Partida #{estado.id} cancelada antes de comenzar")
    GenServer.cast(estado.gestor, {:terminada, estado.id})
    {:noreply, estado}
  end

  # Evita escribir dos veces el mismo resultado si llegan dos avisos de finalización.
  def handle_info(:terminar_partida, %{resultado_guardado: true} = estado) do
    {:noreply, estado}
  end

  def handle_info(:terminar_partida, estado) do
    if estado.timer != nil, do: Process.cancel_timer(estado.timer)
    puntajes_ordenados = Enum.sort_by(estado.puntajes, fn {nombre, valor} -> {-valor, nombre} end)
    maximo = estado.puntajes |> Map.values() |> Enum.max()

    ganadores = puntajes_ordenados
      |> Enum.filter(fn {_nombre, valor} -> valor == maximo end)
      |> Enum.map(fn {nombre, _puntos} -> nombre end)

    registro = %{
      "fecha" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "id" => estado.id,
      "creador" => estado.creador,
      "tema" => estado.tema,
      "nivel" => estado.nivel,
      "ganadores" => ganadores,
      "puntajes" => estado.puntajes
    }

    guardado = Trivia.Persistencia.guardar_resultado(registro)

    enviar_todos(estado, :fin, %{
      id: estado.id,
      tema: estado.tema,
      nivel: estado.nivel,
      ranking: puntajes_ordenados,
      ganadores: ganadores,
      guardado: guardado
    })

    GenServer.cast(estado.gestor, {:terminada, estado.id})
    {:noreply, %{estado | estado: :finalizada, ronda_abierta: false, resultado_guardado: true}}
  end

  def handle_info(_otro, estado), do: {:noreply, estado}
 def terminate(_motivo, estado) do
    Enum.each(estado.bots, fn bot -> send(bot.pid, :detener) end)
    :ok
  end

  defp registrar_respuesta(estado, usuario, letra) do
    letra = String.upcase(String.trim(letra))

    case validar_respuesta(estado, usuario, letra) do
      :ok ->
        restante = tiempo_restante(estado)

        if restante == 0 do
          {estado, {:error, "El tiempo de la pregunta se agotó"}}
        else
          guardar_respuesta(estado, usuario, letra, restante)
        end

      error -> {estado, error}
    end
  end

  defp guardar_respuesta(estado, usuario, letra, restante) do
    if usuario == estado.creador and estado.opciones_ronda_5050 != nil and
         not Map.has_key?(estado.opciones_ronda_5050, letra) do
      {estado, {:error, "Esa opción fue eliminada por el comodín 50/50"}}
    else
      entrada = %{letra: letra, restantes_ms: restante}
      nuevo = %{estado | respuestas: Map.put(estado.respuestas, usuario, entrada)}
      cantidad = 1 + length(estado.bots)
      completo = map_size(nuevo.respuestas) == cantidad
      nuevo = if completo, do: cerrar_ronda(nuevo), else: nuevo
      {nuevo, {:ok, "Respuesta registrada"}}
    end
  end

  defp cerrar_ronda(estado) do
    if estado.timer != nil, do: Process.cancel_timer(estado.timer)
    pregunta = Enum.at(estado.preguntas, estado.indice)
    nombres = [estado.creador | Enum.map(estado.bots, fn bot -> bot.nombre end)]

    {nuevos_puntajes, resumen} = Enum.reduce(nombres, {estado.puntajes, []}, fn nombre, {puntajes, filas} ->
      respuesta = Map.get(estado.respuestas, nombre)

      cambio =
        case respuesta do
          nil -> 0
          %{letra: letra, restantes_ms: restante} ->
            Trivia.Puntaje.calcular_con_comodines(
              pregunta["nivel"], letra, pregunta["respuesta"], restante, estado.tiempo_ms,
              nombre == estado.creador and estado.ronda_5050,
              nombre == estado.creador and estado.ronda_doble
            )
        end

      puntajes = Map.update!(puntajes, nombre, fn previo -> previo + cambio end)
      fila = %{nombre: nombre, cambio: cambio, total: Map.fetch!(puntajes, nombre)}
      {puntajes, filas ++ [fila]}
    end)

    enviar_todos(estado, :cierre, %{
      ronda: estado.indice + 1,
      correcta: pregunta["respuesta"],
      opcion: pregunta["opciones"][pregunta["respuesta"]],
      resultados: resumen
    })

    nuevo = %{estado |
      ronda_abierta: false,
      timer: nil,
      puntajes: nuevos_puntajes,
      respuestas: %{},
      indice: estado.indice + 1
    }

    if nuevo.indice >= nuevo.total do
      send(self(), :terminar_partida)
    else
      Process.send_after(self(), :siguiente_ronda, 3000)
    end

    nuevo
  end

  defp enviar(receptor, tipo, mensaje), do: send(receptor, {:trivia, tipo, mensaje})

  defp tiempo_restante(estado) do
    max(0, estado.tiempo_ms - (System.monotonic_time(:millisecond) - estado.inicio_ms))
  end

  defp enviar_todos(estado, tipo, mensaje) do
    enviar(estado.receptor, tipo, mensaje)
    Enum.each(estado.bots, fn bot -> enviar(bot.pid, tipo, mensaje) end)
  end
end
