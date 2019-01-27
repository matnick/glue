# Glial
[![](https://img.shields.io/travis/glial-iot/glial/develop.svg?label=integration%20tests)](https://travis-ci.org/glial-iot/glial) ![](https://img.shields.io/github/last-commit/glial-iot/glial.svg) ![](https://img.shields.io/github/commit-activity/y/glial-iot/glial.svg) ![](https://img.shields.io/github/tag-date/glial-iot/glial.svg?label=last%20version)  
![](https://img.shields.io/github/languages/top/glial-iot/glial.svg) ![](https://img.shields.io/github/languages/code-size/glial-iot/glial.svg) ![](https://img.shields.io/github/repo-size/glial-iot/glial.svg) ![](https://img.shields.io/github/license/glial-iot/glial.svg)  

<!-- ![](https://img.shields.io/github/issues-raw/glial-iot/glial.svg) ![](https://img.shields.io/github/issues-closed-raw/glial-iot/glial.svg) -->


## Как запустить Glial?

1. Установите [Tarantool](https://www.tarantool.io/en/download/) и libmosquitto-dev(из репозитория вашей системы)
1. Клонируйте репозиторий: ```git clone https://github.com/glial-iot/glial.git && cd glial```
1. Установите дополнительные пакеты: tarantoolctl rocks install http && tarantoolctl rocks install mqtt && tarantoolctl rocks install dump && tarantoolctl rocks install cron-parser
1. Запустите Glial: ```./glial.lua``` 
1. Откройте панель управления по адресу localhost:8080

## Что это?
Glial — это система управления IoT-устройствами, предоставляющая:
- интерфейс для разработки драйверов, которые получают и конвертируют данные с устройств
- интерфейс для разработки скриптов, которые обеспечивают взаимодействие устройств между собой
- центральную шину данных для хранения текущих данных подключенных устройств
- панель управления для визуализации данных, просмотра логов и настройки системы

## Документация

[Подробная документация](https://glial.pro/docs/)

## Зачем?
Устройства интернета вещей — весьма различны в своих возможностях и характеристиках. Из-за физических ограничений они оперируют множеством протоколов и стандартов: modbus, ethernet, knx, 6lowpan, zigbee, LoRa, и многими другими.

Принять какой-либо стандарт в качестве единого невозможно, так как на данном этапе развития технологий невозможно обеспечить избыточность в стандарте, достаточную для удовлетворения всех задач одновременно: кому-то необходима высокая скорость связи и mesh-сеть, кому-то большая дальность, в каких-то условиях вообще невозможно использовать радио-протоколы.

Таким образом, текущая ситуация в современном интернете вещей заключается в том, что у нас есть множество стандартов передачи данных, и решения этой проблемы в ближайшие годы не предвидится.

### Чем Glial не является?
- Генератором красивых веб-панелей управления
- Графическим конфигуратором
- Панелью управления умным домом
- Средством настройки для устройств, которые производим мы
- Генератором прошивок для Arduino
- Монструозной системой, на обучение которой надо потратить месяц
- Закрытой вендорским продуктом с принципом "что дали тем и пользуйтесь"
- Системой с готовым набором драйверов и скриптов на все случаи жизни

### Тогда что такое Glial?
- Система, ориентированная на разработчиков: предполагается, что писать код вам привычнее, чем расставлять курсором элементы
- Система, ориентированная на простоту разработки: по нашему мнению, разработчик логики не должен вникать в работу системы на низком уровне.
- Системой с открытом кодом: Glial(а так же Tarantool и Lua, которые лежат в его основе) имеют открытый код, что позволяет легко предлагать и дописывать новый функционал.
