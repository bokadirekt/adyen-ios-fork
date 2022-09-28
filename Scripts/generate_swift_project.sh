#!/bin/sh

# Any subsequent(*) commands which fail will cause the shell script to exit immediately
set -eo pipefail

YELLOW='\033[1;33m'
NOCOLOR='\033[0m'
RED='\033[0;31m'

MAX_ATTEMP=3
PACKAGES=("Adyen" "AdyenActions" "AdyenCard" "AdyenComponents" "AdyenSession" "AdyenDropIn" "AdyenSwiftUI" "AdyenEncryption")
INCLUDE_WECHAT=false
PROJECT_NAME=TempProject
NO_CLEAN=false

function print_help {
  echo "Generate test fixture based on swift"
  echo " "
  echo "  generate_swift_project [pods|spm|carthage] [-t DEVELOPMENT_TEAM] [-w] [-p PROJECT_NAME]"
  echo " "
  echo "parameters:"
  echo "  pods                      generate project for CocoaPods"
  echo "  spm                       generate project for SPM"
  echo "  carthage                  generate project for Carthage"
  echo " "
  echo "options:"
  echo "  -w, --include-wechat      include wechat module"
  echo "  -t, --team                set DEVELOPMENT_TEAM to all bundle modules"
  echo "  -p, --project             set project name and folder. Default: TempProject"
  echo "  -c, --no-clean            prevent removing of project folderr before. Default: false"
}

function echo_header {
  echo " "
  echo "############# $1 #############"
}

function echo_error {
  echo " "
  echo "${RED}## error: $1${NOCOLOR}"
  exit 1
}

function echo_warning {
  echo " "
  echo "${YELLOW}## warning: $1${NOCOLOR}"
}

function add_spm_dependency {
  echo "                  .product(name: \"$1\", package: \"Adyen\"),"  >> Package.swift
}

function add_pods_development_team {
    echo "" >> Podfile
    echo "post_install do |installer|" >> Podfile
    echo "  installer.generated_projects.each do |project|" >> Podfile
    echo "    project.targets.each do |target|" >> Podfile
    echo "        target.build_configurations.each do |config|" >> Podfile
    echo "            config.build_settings[\"DEVELOPMENT_TEAM\"] = \"$1\"" >> Podfile
    echo "        end" >> Podfile
    echo "    end" >> Podfile
    echo "  end" >> Podfile
    echo "end" >> Podfile
}

function add_pods_dependency {
  # replace first instance of `Adyen` with `Adyen/` only
  if [ $1 = "Adyen" ]; then
    local POD_NAME='Adyen/Core'
  else
    local POD_NAME=${1/Adyen/Adyen\/}
  fi
  echo "  pod '$POD_NAME', :path => '../'" >> Podfile
}

function add_carthage_dependency {
  echo "        .binaryTarget(" >> Package.swift
  echo "            name: \"$1\"," >> Package.swift
  echo "            path: \"Carthage/Build/$1.xcframework\")," >> Package.swift
}

function generat_project {
  swift package init
  echo "// swift-tools-version:5.3" > Package.swift
  echo "// The swift-tools-version declares the minimum version of Swift required to build this package."  >> Package.swift
  echo ""  >> Package.swift
  echo "import PackageDescription"  >> Package.swift
  echo ""  >> Package.swift
  echo "let package = Package("  >> Package.swift
  echo "    name: \"TempProject\","  >> Package.swift
  echo "    defaultLocalization: \"en-US\","  >> Package.swift
  echo "    platforms: ["  >> Package.swift
  echo "        .iOS(.v11)"  >> Package.swift
  echo "    ],"  >> Package.swift
  echo "    products: ["  >> Package.swift
  echo "        .library("  >> Package.swift
  echo "            name: \"TempProject\","  >> Package.swift
  echo "            targets: [\"TempProject\"]"  >> Package.swift
  echo "        )"  >> Package.swift
  echo "    ],"  >> Package.swift
  echo "    dependencies: ["  >> Package.swift
  if [ $PROJECT_TYPE = "spm" ]; then
    echo "        .package(name: \"Adyen\", path: \"../\"),"  >> Package.swift
  fi
  echo "    ],"  >> Package.swift
  echo "    targets: ["  >> Package.swift
  echo "        .target("  >> Package.swift
  echo "            name: \"TempProject\","  >> Package.swift
  echo "            dependencies: [" >> Package.swift

  case $PROJECT_TYPE in
    'pods')
      echo "            ])," >> Package.swift
      ;;
    'spm')
      for package in ${PACKAGES[@]}; do
        add_spm_dependency $package
      done
      if [ "$INCLUDE_WECHAT" = true ]; then
        add_spm_dependency "AdyenWeChatPay"
      fi
      echo "            ])," >> Package.swift
      ;;
    'carthage')
      echo "            ])," >> Package.swift
      for package in ${PACKAGES[@]}; do
        add_carthage_dependency $package
      done
      if [ "$INCLUDE_WECHAT" = true ]; then
        add_carthage_dependency "AdyenWeChatPay"
      fi
      ;;
  esac

  echo "    ]" >> Package.swift
  echo ")" >> Package.swift
}

function setup_dependency_manager {
  case $PROJECT_TYPE in
    'pods')
      # Generating Podfile
      echo "platform :ios, '11.0'" >> Podfile
      echo "" >> Podfile
      echo "target '$PROJECT_NAME' do" >> Podfile
      echo "  use_frameworks!" >> Podfile
      for package in ${PACKAGES[@]}; do
        add_pods_dependency $package
      done
      if [ "$INCLUDE_WECHAT" = true ]; then
        add_pods_dependency "AdyenWeChatPay"
      fi
      echo "end" >> Podfile

      if [ ! -z "$DEVELOPMENT_TEAM" ]; then
        add_pods_development_team $DEVELOPMENT_TEAM
      fi

      echo_header "Generating xcodeproj"
      swift package generate-xcodeproj

      echo_header "Install Pods"
      pod install
      ;;
    'spm')
      echo_header "Update SPM"
      swift package update
      swift package resolve

      local ATTEMPT=0
      while [ -z $SUCCESS ] && [ "$ATTEMPT" -le "$MAX_ATTEMP" ]; do
        xcodebuild clean -scheme $PROJECT_NAME -destination 'generic/platform=iOS' | grep -q "CLEAN SUCCEEDED" && SUCCESS=true
        ATTEMPT=$(($ATTEMPT+1))
        echo "Waiting for PIF: $ATTEMPT"
      done
      ;;
    'carthage')
      ;;
  esac
}

while [[ $# -ne 0 ]]; do
  case $1 in
    -h|--help)
      print_help
      exit 0
      ;;
    -p|--project)
      PROJECT_NAME="$2"
      shift 2
      ;;
    -w|--include-wechat)
      INCLUDE_WECHAT=true
      shift
      ;;
    -c|--no-clean)
      NO_CLEAN=true
      shift
      ;;
    -t|--team)
      DEVELOPMENT_TEAM="$2"
      shift 2
      ;;
    'pods')
      PROJECT_TYPE='pods'
      shift
      ;;
    'spm')
      PROJECT_TYPE='spm'
      shift
      ;;
    'carthage')
      PROJECT_TYPE='carthage'
      shift
      ;;
    *)
      echo_warning "Unknown parameter: $1"
      shift
      ;;
  esac
done

if [ -z "$PROJECT_TYPE" ]; then
  echo_error "Project type not specified! Call --help for more info"
fi

echo_header "Create a new Xcode project in $PROJECT_NAME"
if [ $NO_CLEAN = false ]; then
  rm -rf $PROJECT_NAME
fi
mkdir -p $PROJECT_NAME && cd $PROJECT_NAME

echo_header 'Generating project'
generat_project

setup_dependency_manager
