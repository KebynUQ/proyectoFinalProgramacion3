defmodule Trivia.ComodinesTest do
  use ExUnit.Case

  defp con_datos(funcion) do
    original = File.cwd!()
    on_exit(fn -> File.cd!(original) end)
    carpeta = Path.join(System.tmp_dir!(),
      "trivia_comodines_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(carpeta, "data"))
    File.cp!(Path.join([original, "data", "questions.json"]),
      Path.join([carpeta, "data", "questions.json"]))
    File.write!(Path.join([carpeta, "data", "users.json"]), "{}")
    File.write!(Path.join([carpeta, "data", "results.log"]), "")
    File.cd!(carpeta, fn ->
      start_supervised!(Trivia.Persistencia)
      start_supervised!(Trivia.BancoPreguntas)
      funcion.()
    end)
  end

  defp iniciar_partida(total, tiempo) do
    opciones = [
      id: "P-1001", creador: "ana", receptor: self(), gestor: self(),
      tema: "ciencia", nivel: "basico", total: total, tiempo: tiempo
    ]
    pid = start_supervised!({Trivia.Partida, opciones})
    assert {:ok, _} = Trivia.Partida.agregar_bot(pid, "facil")
    assert {:ok, _} = Trivia.Partida.agregar_bot(pid, "dificil")
    assert {:ok, _} = Trivia.Partida.comenzar(pid)
    assert_receive {:trivia, :pregunta, pregunta}, 1000
    {pid, pregunta}
  end

  defp correcta(pid, indice) do
    :sys.get_state(pid).preguntas
    |> Enum.at(indice)
    |> Map.fetch!("respuesta")
  end

  defp cierre_humano do
    assert_receive {:trivia, :cierre, datos}, 3000
    Enum.find(datos.resultados, fn fila -> fila.nombre == "ana" end).cambio
  end

  test "50/50 conserva la correcta, una incorrecta y las letras originales" do
    opciones = %{"A" => "uno", "B" => "dos", "C" => "tres", "D" => "cuatro"}

    Enum.each(1..40, fn _ ->
      reducidas = Trivia.Partida.opciones_5050(opciones, "C")
      assert map_size(reducidas) == 2
      assert reducidas["C"] == "tres"
      assert Enum.all?(reducidas, fn {letra, texto} -> opciones[letra] == texto end)
      assert Enum.count(reducidas, fn {letra, _} -> letra != "C" end) == 1
    end)
  end

  test "el cálculo conserva las reglas normales y aplica ambos comodines en orden" do
    p = Trivia.Puntaje
    assert p.calcular_con_comodines("basico", "A", "A", 14_000, 15_000, false, false) == 14
    assert p.calcular_con_comodines("basico", "A", "A", 14_000, 15_000, true, false) == 10
    assert p.calcular_con_comodines("basico", "A", "A", 14_000, 15_000, false, true) == 28
    assert p.calcular_con_comodines("basico", "A", "A", 14_000, 15_000, true, true) == 20
    assert p.calcular_con_comodines("basico", "B", "A", 14_000, 15_000, false, true) == -10
    assert p.calcular_con_comodines("intermedio", "B", "A", 14_000, 15_000, false, true) == -16
    assert p.calcular_con_comodines("avanzado", "A", "A", 0, 15_000, false, true) == 40
    assert p.calcular_con_comodines("basico", nil, "A", 0, 15_000, false, true) == 0
  end

  test "50/50 reenvía solo dos opciones sin reiniciar tiempo ni dar bonificación" do
    con_datos(fn ->
      {pid, pregunta} = iniciar_partida(1, 2)
      estado_antes = :sys.get_state(pid)
      assert {:error, _} = Trivia.Partida.usar_comodin(pid, "ana", "desconocido", pregunta.token)
      assert :sys.get_state(pid).uso_5050 == false
      Process.sleep(200)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", pregunta.token)
      assert_receive {:trivia, :pregunta_5050, reducida}
      assert map_size(reducida.opciones) == 2
      assert Map.has_key?(reducida.opciones, correcta(pid, 0))
      refute Map.has_key?(reducida, :respuesta)
      assert reducida.tiempo_restante_ms < 2000
      assert :sys.get_state(pid).inicio_ms == estado_antes.inicio_ms
      assert :sys.get_state(pid).timer == estado_antes.timer
      assert {:error, mensaje} = Trivia.Partida.usar_comodin(pid, "ana", "5050", pregunta.token)
      assert String.contains?(mensaje, "Ya utilizaste")
      eliminada = Enum.find(["A", "B", "C", "D"], fn letra ->
        not Map.has_key?(reducida.opciones, letra)
      end)
      assert {:error, _} = Trivia.Partida.responder(pid, "ana", eliminada)
      refute Map.has_key?(:sys.get_state(pid).respuestas, "ana")
      assert {:ok, _} = Trivia.Partida.responder(pid, "ana", correcta(pid, 0))
      assert cierre_humano() == 10
    end)
  end

  test "Doble multiplica solo la penalización humana y no afecta la ronda siguiente" do
    con_datos(fn ->
      {pid, pregunta} = iniciar_partida(2, 1)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "doble", pregunta.token)
      assert {:error, mensaje} = Trivia.Partida.usar_comodin(pid, "ana", "doble", pregunta.token)
      assert String.contains?(mensaje, "Ya utilizaste")
      mala = Enum.find(["A", "B", "C", "D"], fn letra -> letra != correcta(pid, 0) end)
      assert {:ok, _} = Trivia.Partida.responder(pid, "ana", mala)
      assert cierre_humano() == -10
      assert_receive {:trivia, :pregunta, siguiente}, 4500
      assert :sys.get_state(pid).uso_doble
      refute :sys.get_state(pid).ronda_doble
      assert {:error, mensaje} = Trivia.Partida.usar_comodin(pid, "ana", "doble", siguiente.token)
      assert String.contains?(mensaje, "Ya utilizaste")
      assert {:ok, _} = Trivia.Partida.responder(pid, "ana", correcta(pid, 1))
      assert cierre_humano() in 10..15
    end)
  end

  test "Doble en una ronda sin respuesta mantiene cero puntos" do
    con_datos(fn ->
      {pid, pregunta} = iniciar_partida(1, 1)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "doble", pregunta.token)
      assert cierre_humano() == 0
    end)
  end

  test "50/50 conserva la penalización y no modifica los puntos de los bots" do
    con_datos(fn ->
      {pid, pregunta} = iniciar_partida(1, 1)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", pregunta.token)
      assert_receive {:trivia, :pregunta_5050, reducida}
      mala = Enum.find(Map.keys(reducida.opciones), fn letra -> letra != correcta(pid, 0) end)
      assert {:ok, _} = Trivia.Partida.responder(pid, "ana", mala)
      assert_receive {:trivia, :cierre, datos}, 2000
      assert Enum.find(datos.resultados, fn fila -> fila.nombre == "ana" end).cambio == -5
      bots = Enum.filter(datos.resultados, fn fila -> fila.nombre != "ana" end)
      assert Enum.all?(bots, fn fila -> fila.cambio == -5 or fila.cambio in 10..15 end)
    end)
  end

  test "50/50 se consume una vez pero su efecto no pasa a la siguiente ronda" do
    con_datos(fn ->
      {pid, primera} = iniciar_partida(2, 1)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", primera.token)
      assert_receive {:trivia, :pregunta_5050, _}
      assert {:ok, _} = Trivia.Partida.responder(pid, "ana", correcta(pid, 0))
      assert cierre_humano() == 10

      assert_receive {:trivia, :pregunta, segunda}, 4500
      estado = :sys.get_state(pid)
      assert estado.uso_5050
      refute estado.ronda_5050
      assert estado.opciones_ronda_5050 == nil
      assert {:error, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", segunda.token)
      assert {:ok, _} = Trivia.Partida.responder(pid, "ana", correcta(pid, 1))
      assert cierre_humano() in 10..15
    end)
  end

  for orden <- [["5050", "doble"], ["doble", "5050"]] do
    test "ambos comodines en orden #{Enum.join(orden, " luego ")} dan 20 puntos" do
      con_datos(fn ->
        {pid, pregunta} = iniciar_partida(1, 2)

        Enum.each(unquote(orden), fn tipo ->
          assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", tipo, pregunta.token)
        end)

        assert_receive {:trivia, :pregunta_5050, _reducida}
        assert {:ok, _} = Trivia.Partida.responder(pid, "ana", correcta(pid, 0))
        assert cierre_humano() == 20
      end)
    end
  end

  test "se rechazan usos antes, después de responder, en pausa y con token anterior" do
    con_datos(fn ->
      opciones = [
        id: "P-1001", creador: "ana", receptor: self(), gestor: self(),
        tema: "ciencia", nivel: "basico", total: 2, tiempo: 1
      ]
      pid = start_supervised!({Trivia.Partida, opciones})
      assert {:error, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", nil)
      Trivia.Partida.agregar_bot(pid, "facil")
      Trivia.Partida.agregar_bot(pid, "dificil")
      Trivia.Partida.comenzar(pid)
      assert_receive {:trivia, :pregunta, primera}
      assert {:ok, _} = Trivia.Partida.responder(pid, "ana", correcta(pid, 0))
      assert {:error, mensaje} = Trivia.Partida.usar_comodin(pid, "ana", "doble", primera.token)
      assert String.contains?(mensaje, "después de responder")
      cierre_humano()
      assert {:error, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", primera.token)
      assert_receive {:trivia, :pregunta, segunda}, 4500
      assert {:error, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", primera.token)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", segunda.token)
      assert_receive {:trivia, :pregunta_5050, _}
      assert :sys.get_state(pid).uso_5050
    end)
  end

  test "un comodín que llega después del vencimiento no se consume" do
    con_datos(fn ->
      {pid, pregunta} = iniciar_partida(1, 1)
      :ok = :sys.suspend(pid)
      Process.sleep(900)
      padre = self()
      spawn(fn ->
        send(padre, {:vencido, Trivia.Partida.usar_comodin(pid, "ana", "5050", pregunta.token)})
      end)
      Process.sleep(250)
      :ok = :sys.resume(pid)
      assert_receive {:vencido, {:error, _}}, 2000
      refute :sys.get_state(pid).uso_5050
    end)
  end

  test "al terminar se rechaza el comodín y un juego nuevo lo ofrece otra vez" do
    con_datos(fn ->
      {pid, pregunta} = iniciar_partida(1, 2)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", pregunta.token)
      assert {:ok, _} = Trivia.Partida.usar_comodin(pid, "ana", "doble", pregunta.token)
      assert_receive {:trivia, :pregunta_5050, _}
      assert {:ok, _} = Trivia.Partida.abandonar(pid)
      assert_receive {:trivia, :fin, _}, 1000
      assert {:error, _} = Trivia.Partida.usar_comodin(pid, "ana", "5050", pregunta.token)
      stop_supervised(Trivia.Partida)

      opciones = [
        id: "P-1002", creador: "ana", receptor: self(), gestor: self(),
        tema: "ciencia", nivel: "basico", total: 1, tiempo: 2
      ]
      nuevo = start_supervised!({Trivia.Partida, opciones})
      refute :sys.get_state(nuevo).uso_5050
      refute :sys.get_state(nuevo).uso_doble
    end)
  end

  test "el servidor rechaza un comodín solicitado con otra sesión" do
    con_datos(fn ->
      start_supervised!(Trivia.GestorJugadores)
      start_supervised!({DynamicSupervisor,
        strategy: :one_for_one, name: Trivia.SupervisorPartidas})
      start_supervised!(Trivia.GestorPartidas)
      start_supervised!(Trivia.Servidor)
      receptor = self()
      pedir = fn solicitud ->
        GenServer.call(Trivia.Servidor, {:solicitar, receptor, solicitud})
      end
      assert {:ok, _} = pedir.({:connect, "ana", "123"})
      assert {:ok, _} = pedir.({:create_game, "ciencia", 1, 2})
      assert {:ok, _} = pedir.({:add_bot, "facil"})
      assert {:ok, _} = pedir.({:add_bot, "dificil"})
      assert {:ok, _} = pedir.(:start_game)
      assert_receive {:trivia, :pregunta, pregunta}

      padre = self()
      spawn(fn ->
        send(padre, {:ajena, GenServer.call(Trivia.Servidor,
          {:solicitar, receptor, {:lifeline, "doble", pregunta.token}})})
      end)
      assert_receive {:ajena, {:error, _}}
      assert {:ok, _} = pedir.({:lifeline, "doble", pregunta.token})
    end)
  end

  test "un juego nuevo y una partida reiniciada recuperan los dos comodines" do
    con_datos(fn ->
      supervisor = start_supervised!({DynamicSupervisor,
        strategy: :one_for_one, name: Trivia.SupervisorComodinesTest})
      opciones = [
        id: "P-1001", creador: "ana", receptor: self(), gestor: self(),
        tema: "ciencia", nivel: "basico", total: 1, tiempo: 2
      ]
      {:ok, pid} = DynamicSupervisor.start_child(supervisor, {Trivia.Partida, opciones})
      Trivia.Partida.agregar_bot(pid, "facil")
      Trivia.Partida.agregar_bot(pid, "dificil")
      Trivia.Partida.comenzar(pid)
      assert_receive {:trivia, :pregunta, pregunta}
      Trivia.Partida.usar_comodin(pid, "ana", "5050", pregunta.token)
      Trivia.Partida.usar_comodin(pid, "ana", "doble", pregunta.token)
      Process.exit(pid, :kill)
      Process.sleep(100)
      [{_, nuevo, _, _}] = DynamicSupervisor.which_children(supervisor)
      assert nuevo != pid
      refute :sys.get_state(nuevo).uso_5050
      refute :sys.get_state(nuevo).uso_doble
      refute :sys.get_state(nuevo).ronda_5050
      refute :sys.get_state(nuevo).ronda_doble
      assert {:error, _} = Trivia.Partida.usar_comodin(nuevo, "ana", "5050", nil)
    end)
  end
end

