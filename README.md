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

El submenú **Probar estados** simula cada caso (ícono, parpadeo, sonido y notificación). Mientras está activo no se consulta al SMN; para volver, elegí **Volver a los datos reales**.

## Compilar y abrir

Necesita macOS 13 o superior y las Command Line Tools de Xcode (no hace falta Xcode).

```sh
./build-app.sh
open "build/SMN Alertas.app"
```

Para que abra sola al iniciar sesión, agregala en Configuración del Sistema → General → Ítems de inicio.

## Verificación

```sh
swift run SelfCheck
```
