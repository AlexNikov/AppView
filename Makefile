GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)


TARGET_MAX_CHAR_NUM=20
## Show help
help:
	@echo ''
	@echo 'Использование:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Команды:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${YELLOW}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

## Инициализирует проект: xcodegen + pod install + verify
init:
	@if ! command -v xcodegen > /dev/null 2>&1; then \
		echo "xcodegen is not installed! Run: brew install xcodegen"; \
		exit 1; \
	fi
	@if [ ! -d Pods ]; then \
		echo "Pods/ missing — bootstrap pod install (project.yml references Pods xcconfig)"; \
		pod install; \
	fi
	OPEN_PROJECT=0 bash Scripts/generate_xcode_project.sh

## Полная подготовка проекта
setup: init

## Генерирует проект и открывает workspace
gen: init start

## Позволяет быстро открыть workspace проекта
start: init
	open AppView.xcworkspace

## Устанавливает поды
pod:
	pod install

## Устанавливает поды с обновлением spec-репозиториев
pod_update:
	pod install --repo-update

## Локальная сборка Debug
build:
	xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

## Локальная сборка Release
build-release:
	xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

## Очищает локальный DerivedData
clean:
	rm -rf build/DerivedData
