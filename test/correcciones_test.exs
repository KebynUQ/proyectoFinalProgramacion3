defmodule Trivia.CorreccionesTest do
  use ExUnit.Case

  defp con_datos(funcion) do
    directorio_original = File.cwd!()
    on_exit(fn -> File.cd!(directorio_original) end)
    origen = Path.join([directorio_original, "data", "questions.json"])

    carpeta =
      Path.join(
        System.tmp_dir!(),
        "trivia_test_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(carpeta, "data"))
    File.cp!(origen, Path.join([carpeta, "data", "questions.json"]))
    File.write!(Path.join([carpeta, "data", "users.json"]), "{}")
    File.write!(Path.join([carpeta, "data", "results.log"]), "")
    File.cd!(carpeta, fn -> funcion.(carpeta) end)
  end

  defp iniciar_servicios do
    start_supervised!(Trivia.Persistencia)
    start_supervised!(Trivia.BancoPreguntas)
    start_supervised!(Trivia.GestorJugadores)

    start_supervised!(
      {DynamicSupervisor, strategy: :one_for_one, name: Trivia.SupervisorPartidas}
    )

    start_supervised!(Trivia.GestorPartidas)
    start_supervised!(Trivia.Servidor)
  end

  defp registro(id) do
    %{
      "fecha" => "2026-11-12T00:00:00Z",
      "id" => id,
      "creador" => "ana",
      "tema" => "ciencia",
      "nivel" => "basico",
      "ganadores" => ["ana"],
      "puntajes" => %{"ana" => 10}
    }
  end

  defp esperar_partida_libre(usuario, intentos \\ 50)
  defp esperar_partida_libre(_usuario, 0), do: flunk("La partida no terminó")

  defp esperar_partida_libre(usuario, intentos) do
    if Map.has_key?(:sys.get_state(Trivia.GestorPartidas).por_usuario, usuario) do
      Process.sleep(20)
      esperar_partida_libre(usuario, intentos - 1)
    else
      :ok
    end
  end

  defp esperar_ronda(pid, numero, intentos \\ 100)
  defp esperar_ronda(_pid, _numero, 0), do: flunk("La ronda no se abrió")

  defp esperar_ronda(pid, numero, intentos) do
    estado = :sys.get_state(pid)

    if estado.ronda_abierta and estado.token == numero do
      :ok
    else
      Process.sleep(50)
      esperar_ronda(pid, numero, intentos - 1)
    end
  end

  test "los IDs no se reutilizan tras cancelar, abandonar y reiniciar procesos" do
    con_datos(fn _carpeta ->
      iniciar_servicios()
      assert {:ok, mensaje} = Trivia.GestorPartidas.crear("ana", self(), "ciencia", 1, 1)
      assert String.contains?(mensaje, "P-1001")
      assert {:ok, _} = Trivia.GestorPartidas.abandonar("ana")
      esperar_partida_libre("ana")

      assert {:ok, mensaje} = Trivia.GestorPartidas.crear("ana", self(), "ciencia", 1, 1)
      assert String.contains?(mensaje, "P-1002")
      assert {:ok, _} = Trivia.GestorPartidas.agregar_bot("ana", "facil")
      assert {:ok, _} = Trivia.GestorPartidas.agregar_bot("ana", "dificil")
      assert {:ok, _} = Trivia.GestorPartidas.comenzar("ana")
      assert {:ok, _} = Trivia.GestorPartidas.abandonar("ana")
      esperar_partida_libre("ana")

      stop_supervised(Trivia.GestorPartidas)
      stop_supervised(Trivia.Persistencia)
      start_supervised!(Trivia.Persistencia)
      start_supervised!(Trivia.GestorPartidas)
      assert {:ok, mensaje} = Trivia.GestorPartidas.crear("ana", self(), "ciencia", 1, 1)
      assert String.contains?(mensaje, "P-1003")
    end)
  end

  test "el contador nuevo parte después del mayor ID del historial existente" do
    con_datos(fn carpeta ->
      File.write!(
        Path.join([carpeta, "data", "results.log"]),
        Jason.encode!(registro("P-1450")) <> "\n"
      )

      start_supervised!(Trivia.Persistencia)
      assert {:ok, "P-1451"} = Trivia.Persistencia.siguiente_id()
    end)
  end

  test "otro proceso no puede usar el receptor de una sesión ajena" do
    con_datos(fn _carpeta ->
      iniciar_servicios()

      receptor =
        spawn(fn ->
          receive do
            :fin -> :ok
          end
        end)

      assert {:ok, _} =
               GenServer.call(Trivia.Servidor, {:solicitar, receptor, {:connect, "ana", "123"}})

      assert {:ok, _} = GenServer.call(Trivia.Servidor, {:solicitar, receptor, :score})

      padre = self()

      spawn(fn ->
        send(
          padre,
          {:suplantacion,
           GenServer.call(
             Trivia.Servidor,
             {:solicitar, receptor, {:create_game, "ciencia", 1, 1}}
           ), GenServer.call(Trivia.Servidor, {:solicitar, receptor, :disconnect})}
        )
      end)

      assert_receive {:suplantacion, {:error, _}, {:error, _}}
      assert {:ok, "ana"} = Trivia.GestorJugadores.usuario(receptor, self())
      send(receptor, :fin)
    end)
  end

  test "historial inválido informa la línea y bloquea estadísticas y nuevas partidas" do
    con_datos(fn carpeta ->
      iniciar_servicios()

      receptor =
        spawn(fn ->
          receive do
            :fin -> :ok
          end
        end)

      assert {:ok, _} =
               GenServer.call(Trivia.Servidor, {:solicitar, receptor, {:connect, "ana", "123"}})

      File.write!(
        Path.join([carpeta, "data", "results.log"]),
        Jason.encode!(registro("P-1001")) <> "\n{dañado}\n"
      )

      assert {:error, mensaje} = Trivia.Persistencia.historial()
      assert String.contains?(mensaje, "línea 2")
      assert {:error, ^mensaje} = GenServer.call(Trivia.Servidor, {:solicitar, receptor, :score})

      assert {:error, ^mensaje} =
               GenServer.call(Trivia.Servidor, {:solicitar, receptor, {:ranking, nil}})

      assert {:error, ^mensaje} =
               GenServer.call(
                 Trivia.Servidor,
                 {:solicitar, receptor, {:create_game, "ciencia", 1, 1}}
               )

      File.write!(
        Path.join([carpeta, "data", "results.log"]),
        Jason.encode!(registro("P-1001")) <> "\n" <> Jason.encode!(%{"id" => "P-1002"}) <> "\n"
      )

      assert {:error, otro_mensaje} = Trivia.Persistencia.historial()
      assert String.contains?(otro_mensaje, "línea 2")
      send(receptor, :fin)
    end)
  end

  test "el banco identifica preguntas inválidas y niveles incompletos" do
    con_datos(fn carpeta ->
      Process.flag(:trap_exit, true)
      ruta = Path.join([carpeta, "data", "questions.json"])
      preguntas = ruta |> File.read!() |> Jason.decode!()
      [primera | resto] = preguntas
      File.write!(ruta, Jason.encode!([Map.delete(primera, "opciones") | resto]))

      assert {:error, {:banco_preguntas_invalido, {:error, mensaje}}} =
               Trivia.BancoPreguntas.start_link()

      assert String.contains?(mensaje, "Pregunta 1")

      File.write!(ruta, Jason.encode!(Enum.drop(preguntas, 1)))

      assert {:error, {:banco_preguntas_invalido, {:error, mensaje}}} =
               Trivia.BancoPreguntas.start_link()

      assert String.contains?(mensaje, "ciencia")
      assert String.contains?(mensaje, "basico")

      variantes = [
        Map.put(primera, "tema", "Ciencia"),
        Map.put(primera, "nivel", "experto"),
        Map.put(primera, "enunciado", ""),
        Map.put(primera, "respuesta", "E"),
        Map.put(primera, "opciones", %{"A" => "uno", "B" => "dos", "C" => "tres"}),
        Map.put(primera, "opciones", %{"A" => "uno", "B" => "uno", "C" => "tres", "D" => "cuatro"})
      ]

      Enum.each(variantes, fn invalida ->
        File.write!(ruta, Jason.encode!([invalida | resto]))

        assert {:error, {:banco_preguntas_invalido, {:error, mensaje}}} =
                 Trivia.BancoPreguntas.start_link()

        assert String.contains?(mensaje, "Pregunta 1")
      end)

      [segunda | otras] = resto
      repetida = Map.put(segunda, "enunciado", primera["enunciado"])
      File.write!(ruta, Jason.encode!([primera, repetida | otras]))

      assert {:error, {:banco_preguntas_invalido, {:error, mensaje}}} =
               Trivia.BancoPreguntas.start_link()

      assert String.contains?(mensaje, "Pregunta 2")

      File.write!(ruta, "{json inválido")
      assert {:error, {:banco_preguntas_invalido, _}} = Trivia.BancoPreguntas.start_link()
    end)
  end

  test "el bot cancela su respuesta al cerrar la ronda y termina al recibir fin" do
    bot = Trivia.Bot.iniciar("bot_1", "dificil")
    referencia = Process.monitor(bot)

    send(
      bot,
      {:trivia, :pregunta,
       %{nivel: "basico", respuesta: "A", tiempo_ms: 100, partida: self(), token: 1}}
    )

    send(bot, {:trivia, :cierre, %{}})
    refute_receive {:"$gen_call", _, _}, 150
    send(bot, {:trivia, :fin, %{}})
    assert_receive {:DOWN, ^referencia, :process, ^bot, :normal}
  end

  test "una respuesta vencida y un temporizador antiguo no afectan la ronda siguiente" do
    con_datos(fn _carpeta ->
      start_supervised!(Trivia.Persistencia)
      start_supervised!(Trivia.BancoPreguntas)

      opciones = [
        id: "P-1001",
        creador: "ana",
        receptor: self(),
        gestor: self(),
        tema: "ciencia",
        nivel: "basico",
        total: 2,
        tiempo: 1
      ]

      pid = start_supervised!({Trivia.Partida, opciones})
      Trivia.Partida.agregar_bot(pid, "facil")
      Trivia.Partida.agregar_bot(pid, "dificil")
      Trivia.Partida.comenzar(pid)
      esperar_ronda(pid, 1)
      :ok = :sys.suspend(pid)
      Process.sleep(900)
      padre = self()
      spawn(fn -> send(padre, {:tardia, Trivia.Partida.responder(pid, "ana", "A")}) end)
      Process.sleep(250)
      :ok = :sys.resume(pid)
      assert_receive {:tardia, {:error, _}}, 2000

      esperar_ronda(pid, 2)
      send(pid, {:cerrar_por_tiempo, 1})
      Process.sleep(50)
      assert :sys.get_state(pid).ronda_abierta
      assert :sys.get_state(pid).token == 2
    end)
  end
end
