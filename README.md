# SMN Alertas

App de barra de menú para macOS que avisa cuando el Servicio Meteorológico Nacional emite una alerta o un aviso a corto plazo que cubre tu ciudad. Junto con la notificación muestra un informe con los horarios en los que conviene tener más cuidado.

## Cómo funciona

- **Alertas:** cada 5 minutos lee el feed CAP oficial del SMN (`https://ssl.smn.gob.ar/CAP/AR.php`). Es el estándar internacional de alertas y está registrado ante la OMM. Cada alerta trae un polígono, la severidad y el horario de vigencia, y la app revisa si tu ciudad cae dentro del polígono.
- **Horarios de cuidado:** usa el pronóstico por hora de [Open-Meteo](https://open-meteo.com), que es gratis y no pide clave. Marca las horas de las próximas 24 h con tormenta (códigos WMO 95–99), lluvia de 2 mm/h o más, ráfagas de 50 km/h o más, o nieve.
- **Ciudad:** se busca con el geocoding de Open-Meteo, limitado a Argentina.
- **Límite del SMN:** permite 180 descargas de XML cada 10 minutos. La app baja como máximo 80 archivos CAP por consulta, empezando por los avisos a corto plazo y después por tu región. Los archivos se guardan en `~/Library/Application Support/SMNAlertas/cap`, así que solo la primera carga tarda unos 10 minutos.
- **Sin avisos repetidos:** el SMN reemite cada alerta con un identificador nuevo en cada actualización. La app avisa una sola vez por evento, y de nuevo solo si sube el nivel o si la alerta terminó y vuelve.
- **Al despertar la Mac** consulta enseguida, sin esperar al próximo ciclo.

## Ícono, parpadeo y sonido

| Situación | Ícono en la barra |
|---|---|
| Sin alertas | ☁️☀️ en blanco y negro |
| Alerta | ícono del fenómeno (tormenta, lluvia, viento/zonda, nevada) + punto 🟡🟠🔴 |
| Aviso a corto plazo | ⚠️ triángulo relleno + punto de color |

Cuando llega algo nuevo, el punto parpadea y suena un sonido cada 4 segundos hasta que abrís el menú: Ping (amarillo), Hero (naranja) o Sosumi ×3 (rojo). El sonido se corta solo a los 2 minutos y se puede apagar desde el menú. Suena aunque esté activado "No molestar".

Al tocar el ícono se abre un panel con una fila por fenómeno (por ejemplo "Amarilla hasta las 20:59 · luego naranja hasta el mar 02:59"), los detalles y recomendaciones del SMN plegados, y un gráfico de lluvia de las próximas 24 h con las horas de más cuidado. En **Ajustes** se elige la ciudad (con sugerencias), el sonido, el silencio nocturno de las amarillas y si la app abre al iniciar sesión.

En el build de desarrollo, **Probar estados** (menú ··· del panel) simula cada caso. Mientras está activo no se consulta al SMN; para volver, elegí **Volver a los datos reales**.

## Compilar y abrir

Necesita macOS 13 o superior y las Command Line Tools de Xcode (no hace falta Xcode).

```sh
./build-app.sh 1.1.0          # producción: app universal + zip para la release
./build-app.sh 1.1.0 --dev    # desarrollo: agrega "Probar estados" en el menú ··· del panel
open "build/SMN Alertas.app"
```

Genera un binario universal (Intel y Apple silicon) y `build/SMN-Alertas-<versión>.zip` para compartir.

La app tiene una firma local (ad-hoc), no la de un desarrollador de Apple. En otra Mac, la primera vez hay que abrirla con clic derecho → Abrir, o desde Configuración del Sistema → Privacidad y seguridad → "Abrir igualmente".

Para que abra sola al iniciar sesión, agregala en Configuración del Sistema → General → Ítems de inicio.

## Código

- `Sources/SMNCore`: lógica sin interfaz y con tests. Incluye modelos, el parser CAP, las reglas de notificación, el pronóstico y `AlertMonitor`, que consulta al SMN; la red y el disco se inyectan, así que los tests simulan el SMN.
- `Sources/SMNAlertas`: la app. `AppModel` es la fuente única de estado; `PanelView` y `SettingsView` (SwiftUI) la muestran; `StatusItemController` maneja el ícono, el parpadeo y el panel; `AlertNotifier` maneja las notificaciones y el sonido.
- Compila en modo Swift 6, con el chequeo estricto de concurrencia.

## Tests

```sh
swift test          # lógica (Swift Testing), con el SMN simulado y archivos reales del SMN como muestra
./smoke-test.sh     # abre la app compilada y verifica que arranca, consulta al SMN y tiene permiso de notificaciones
```

La interfaz se revisa a mano con "Probar estados" (build de desarrollo) o generando capturas de cada estado, en modo claro y oscuro:

```sh
"build/SMN Alertas.app/Contents/MacOS/SMNAlertas" --snapshots /tmp/smn-capturas   # solo build de desarrollo
```
