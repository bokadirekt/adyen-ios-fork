#!/bin/sh

# Any subsequent(*) commands which fail will cause the shell script to exit immediately
set -eo pipefail

YELLOW='\033[1;33m'
NOCOLOR='\033[0m'
RED='\033[0;31m'

PACKAGES=("Adyen" "AdyenActions" "AdyenCard" "AdyenComponents" "AdyenSession" "AdyenDropIn" "AdyenSwiftUI" "AdyenEncryption")
INCLUDE_WECHAT=false
PROJECT_NAME=TempProject
APP_NAME=${PROJECT_NAME}_App
MAX_ATTEMP=3
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

function add_spm_package {
  if [ $1 = "Adyen" ]; then
    local GROUP_NAME='Adyen'
  else
    local GROUP_NAME="Adyen/$1"
  fi
  echo "  $1:" >> project.yml
  echo "    path: ../" >> project.yml
  echo "    group: $GROUP_NAME" >> project.yml
}

function add_spm_dependency {
  echo "    - package: $1" >> project.yml
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
  echo "      - framework: Carthage/Build/$1.xcframework" >> project.yml
  echo "        embed: true" >> project.yml
  echo "        codeSign: true" >> project.yml
}

function generat_project {
  echo_header "Generate Project"
  echo "name: $PROJECT_NAME" >> project.yml

  case $PROJECT_TYPE in
    'pods')
      ;;
    'spm')
      echo "packages:" >> project.yml
      for package in ${PACKAGES[@]}; do
        add_spm_package $package
      done
      if [ "$INCLUDE_WECHAT" = true ]; then
        add_spm_package "AdyenWeChatPay"
      fi
      ;;
    'carthage')
      ;;
  esac

  echo "targets:" >> project.yml
  echo "  $PROJECT_NAME:" >> project.yml
  echo "    type: application" >> project.yml
  echo "    platform: iOS" >> project.yml
  echo "    sources: Source" >> project.yml
  echo "    testTargets: Tests" >> project.yml
  echo "    settings:" >> project.yml
  echo "      base:" >> project.yml
  echo "        INFOPLIST_FILE: Source/UIKit/Info.plist" >> project.yml
  echo "        PRODUCT_BUNDLE_IDENTIFIER: com.adyen.$PROJECT_NAME" >> project.yml
  if [ ! -z "$DEVELOPMENT_TEAM" ]; then
    echo "        DEVELOPMENT_TEAM: $DEVELOPMENT_TEAM" >> project.yml
  fi
  echo "        CFBundleVersion: 1.0" >> project.yml

  case $PROJECT_TYPE in
    'pods')
      ;;
    'spm')
      echo "    dependencies:" >> project.yml
      for package in ${PACKAGES[@]}; do
        add_spm_dependency $package
      done
      if [ "$INCLUDE_WECHAT" = true ]; then
        add_spm_dependency "AdyenWeChatPay"
      fi
      ;;
    'carthage')
      echo "    dependencies:" >> project.yml
      for package in ${PACKAGES[@]}; do
        add_carthage_dependency $package
      done
      if [ "$INCLUDE_WECHAT" = true ]; then
        add_carthage_dependency "AdyenWeChatPay"
      fi
      ;;
  esac

  echo "  Tests:" >> project.yml
  echo "    type: bundle.ui-testing" >> project.yml
  echo "    platform: iOS" >> project.yml
  echo "    sources: Tests" >> project.yml
  echo "    settings:" >> project.yml
  echo "      base:" >> project.yml
  echo "        CFBundleVersion: 1.0" >> project.yml
  echo "        GENERATE_INFOPLIST_FILE: YES" >> project.yml
  echo "schemes:" >> project.yml
  echo "  $APP_NAME:" >> project.yml
  echo "    build:" >> project.yml
  echo "      targets:" >> project.yml
  echo "        $PROJECT_NAME: all" >> project.yml
  echo "        Tests: [tests]" >> project.yml
  echo "    test:" >> project.yml
  echo "      commandLineArguments: \"-UITests\"" >> project.yml
  echo "      targets:" >> project.yml
  echo "        - Tests" >> project.yml

  mkdir -p Tests
  mkdir -p Source
  cp "../Tests/DropIn Tests/DropInTests.swift" Tests/DropInTests.swift
  cp "../Tests/Helpers/XCTestCaseExtensions.swift" Tests/XCTestCaseExtensions.swift
  cp "../Tests/DummyData/Dummy.swift" Tests/Dummy.swift
  cp -a "../Demo/Common" Source/
  cp -a "../Demo/UIKit" Source/
  cp "../Demo/Configuration.swift" Source/Configuration.swift

  xcodegen generate
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

      echo_header "Install Pods"
      pod install
      ;;
    'spm')
      echo_header "Update SPM"
      swift package update
      swift package resolve

      local ATTEMPT=0
      while [ -z $SUCCESS ] && [ "$ATTEMPT" -le "$MAX_ATTEMP" ]; do
        xcodebuild clean -scheme $APP_NAME -destination 'generic/platform=iOS' | grep -q "CLEAN SUCCEEDED" && SUCCESS=true
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
    -t|--team)
      DEVELOPMENT_TEAM="$2"
      shift 2
      ;;
    -c|--no-clean)
      NO_CLEAN=true
      shift
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
