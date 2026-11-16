# SMN Alertas

App de barra de menú para macOS que avisa cuando el Servicio Meteorológico Nacional emite una alerta o un aviso a corto plazo que cubre tu ciudad. Junto con la notificación muestra un informe con los horarios en los que conviene tener más cuidado.

## Cómo funciona

- **Alertas:** cada 5 minutos lee el feed CAP oficial del SMN (`https://ssl.smn.gob.ar/CAP/AR.php`). Es el estándar internacional de alertas y está registrado ante la OMM. Cada alerta trae un polígono, la severidad y el horario de vigencia, y la app revisa si tu ciudad cae dentro del polígono.
- **Horarios de cuidado:** usa el pronóstico por hora de [Open-Meteo](https://open-meteo.com), que es gratis y no pide clave. Marca las horas de las próximas 24 h con tormenta (códigos WMO 95–99), lluvia de 2 mm/h o más, ráfagas de 50 km/h o más, o nieve.
- **Ciudad:** se busca con el geocoding de Open-Meteo, limitado a Argentina.
- **Límite del SMN:** permite 180 descargas de XML cada 10 minutos. La app baja como máximo 80 archivos CAP por consulta, empezando por los avisos a corto plazo. Al abrirla, revisar todo el país puede tardar unos 10 minutos.

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
