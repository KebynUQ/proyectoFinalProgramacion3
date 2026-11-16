# Proyecto Final - Trivia Concurrente (Programación III)

Universidad del Quindío · Ingeniería de Sistemas y Computación  
Docente: Carlos Andrés Flórez Villarraga

## Equipo

- Kebyn Julián Ochoa Pérez
- Mariana Rodríguez Maya
- Laura Vanessa Guerrero Blanco
- Juan José Téllez Sánchez

## Requisitos

- Erlang/OTP y Elixir (`mix` e `iex`).
- Conexión a internet para obtener una sola vez la dependencia `jason`.
- Tres consolas en el **mismo equipo** para la demostración (un servidor y dos clientes).
- Mismo cookie de Erlang para los tres nodos (en el mismo usuario del mismo equipo generalmente ya coincide).

## Instalación

Desde la carpeta raíz del proyecto (`proyectoFinalProgramacion3`):

```bash
mix deps.get
mix compile
mix test
```

En PowerShell de Windows, puede ser necesario usar `mix.bat` e `iex.bat`, porque `iex` también es un alias de PowerShell:

```powershell
mix.bat deps.get
mix.bat compile
mix.bat test
```

## Iniciar servidor y clientes

**Consola 1 — servidor:**

```bash
iex --sname servidor -S mix
```

El servidor inicia automáticamente sus procesos supervisados. Si no se configura el nombre `servidor`, la aplicación no inicia el estado central.

**Consola 2 — cliente 1:**

```bash
iex --sname pedro -S mix
```

En su prompt de IEx:

```elixir
Trivia.Cliente.iniciar()
```

**Consola 3 — cliente 2:**

```bash
iex --sname ana -S mix
```

Y ejecutar también:

```elixir
Trivia.Cliente.iniciar()
```

En PowerShell, cambiar `iex` por `iex.bat` en las órdenes de terminal.

Para la demostración local, el cliente calcula el nodo `servidor@<mismo-host>` a partir del nombre de su nodo; no necesita ingresar un PID. Los clientes nunca cargan el banco de preguntas ni consultan el directorio `data`.

## Partida de ejemplo

Escribir en la consola interactiva del cliente:

```text
connect pedro 1234
create_game tema=ciencia preguntas=5 tiempo=15
add_bot dificil
add_bot facil
start_game
lifeline 5050
lifeline doble
answer <letra_visible>
score
ranking
ranking ciencia
leave_game
disconnect
salir
```

`<letra_visible>` representa una de las letras que permanecen después del 50/50; por ejemplo, escribir `answer A` si A aparece entre ellas. La respuesta debe escribirse **cuando la pregunta esté abierta**, no antes. El sistema acepta una sola respuesta válida por ronda; entre rondas hay tres segundos de pausa. Para volver a jugar, crear otra partida después de que termine la anterior.

En el segundo cliente, iniciar sesión como otro usuario y crear una partida con `tema=historia`, otro tiempo y otros bots para ver dos partidas al mismo tiempo.

## Comodines del jugador humano

Cada partida nueva ofrece **un 50/50 y un Doble**. Se pueden usar juntos o en rondas distintas, únicamente mientras hay una pregunta abierta y antes de responder. No se pueden reutilizar durante la misma partida. Si la partida falla y se reinicia, vuelven a estar disponibles porque el juego comienza desde cero.

- `lifeline 5050`: vuelve a mostrar **solo al jugador que lo pidió** la pregunta con su opción correcta y una incorrecta elegida al azar. Conserva las letras originales y el tiempo que quedaba; no revela cuál es la correcta. Las letras eliminadas se rechazan sin consumir la respuesta. La bonificación por rapidez de esa ronda es cero. Ejemplo: de A) Bogotá, B) Lima, C) Quito, D) Caracas podrían quedar A) Bogotá y C) Quito.
- `lifeline doble`: duplica los puntos positivos **y negativos** de esa ronda para ese jugador. Por ejemplo, +14 pasa a +28 y -5 pasa a -10. Sin respuesta, 0 sigue siendo 0.

Con ambos en una pregunta básica correcta, el 50/50 elimina la bonificación y Doble multiplica +10 por dos: el resultado es **+20**. Los bots conservan su puntuación normal.

## Comandos

| Comando | Función |
|---|---|
| `connect usuario clave` | Registro o inicio de sesión |
| `disconnect` | Desconecta al jugador |
| `create_game tema=ciencia preguntas=5 tiempo=15` | Crea una partida |
| `add_bot facil` / `add_bot dificil` | Agrega bot, máximo tres |
| `start_game` | Inicia cuando hay al menos dos bots |
| `answer A` | Responde una ronda abierta |
| `lifeline 5050` | Deja dos opciones y anula el bono de rapidez de esa ronda |
| `lifeline doble` | Duplica puntos ganados o perdidos en esa ronda |
| `leave_game` | Abandona la partida |
| `score` | Muestra estadísticas del usuario |
| `ranking` / `ranking ciencia` | Ranking histórico global o por tema |
| `help` | Ayuda interactiva |
| `salir` | Sale del cliente |

## Arquitectura

- `Application`: inicia los procesos centrales solamente en el nodo `servidor`.
- `Servidor`: entrada única para las solicitudes de todos los clientes.
- `GestorJugadores`: administra sesiones; monitoriza el PID receptor de cada cliente.
- `GestorPartidas`: crea partidas, asocia usuarios, reconoce reinicios y mantiene PID actualizados.
- `Partida`: `GenServer` por partida con respuestas, puntajes y temporizador independiente.
- `DynamicSupervisor`: supervisa y reinicia partidas que fallan.
- `Bot`: proceso independiente enlazado con la partida, programa respuestas mediante `Process.send_after`.
- `BancoPreguntas`: mantiene el banco cargado en memoria y realiza los sorteos por niveles.
- `Nivel`: calcula niveles, distribución y estadísticas del historial.
- `Puntaje`: calcula la puntuación de cada respuesta.
- `Persistencia`: único proceso que **escribe** usuarios e historial; las escrituras se hacen una a la vez.
- `Cliente` y `Receptor`: separan la lectura del teclado y la llegada de notificaciones.

## Persistencia

- `data/questions.json`: **96 preguntas**, 4 temas × 3 niveles × 8 preguntas.
- `data/users.json`: se crea automáticamente si no existe. Se almacena la clave en texto plano porque así lo pide el enunciado; **no reutilizar contraseñas reales**.
- `data/results.log`: un JSON por línea, para calcular estadísticas con Streams.
- `data/last_game_id.txt`: último identificador de partida reservado. Lo escribe únicamente `Persistencia`; evita reutilizar identificadores al reiniciar el servidor.

`users.json`, `results.log` y `last_game_id.txt` están excluidos de Git porque contienen datos que el servidor genera al ejecutarse. `Persistencia` crea los dos primeros al inicio si no existen y calcula el contador a partir del historial cuando falta. `questions.json` sí está en el repositorio.

## Pruebas unitarias

```bash
mix test
```

Hay 32 pruebas ExUnit para el puntaje, el reparto y los umbrales de nivel, la selección sin repetidos, las estadísticas y el ranking, las decisiones de los bots, las reglas de armado de partidas y los dos comodines, incluidos sus límites de tiempo y uso.

El proyecto no incluye la extensión opcional de varios humanos en una misma partida.