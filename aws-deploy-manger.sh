#!/bin/bash

####  Main configurations
export IMAGE_NAME="MaisIntercambio Web Server"
export CONTROL_TAG="MI-VERSIONED-IMAGE"
export VERSION_TAG="MI-VERSION"

## Script constants
export RED='\033[1;31m'
export ORANGE='\033[0;33m'
export YELLOW='\033[1;33m'
export GREEN='\033[1;32m'
export CYAN='\033[0;36m'
export NC='\033[0m'

## Helper functions
function printHeader {
  clear
  echo "######################################################################"
  echo "##  ${1}"
  echo "######################################################################"
}

function printSeparator {
    echo "######################################################################"
}

#####  MAIN MENU  ####
function mainMenuScreen {
  while : 
  do
    printHeader "${IMAGE_NAME} AMI & Deploy Manager"
    echo -e "Escolha uma opcão:"
    echo -e " ${YELLOW}1)${NC} Criar nova versão de imagem AMI à partir dessa máquina"
    echo -e " ${YELLOW}2)${NC} Gerenciar versões AMI disponíves na AWS" 
    echo -e " ${YELLOW}0)${NC} Sair" 
    printSeparator
    read -p "Opcão: " -r -n1
    echo
      
    case "$REPLY" in
      1)
	newAmiScreen
	;;
      2)
	listAmiScreen
	;;
      0)
	printSeparator
	echo -e "${CYAN}Até logo!${NC}"
	printSeparator
	exit 0
	;;
      *)
	echo -e " ${RED}Ei! ${YELLOW} '${REPLY}' ${RED} não é opcão válida! Vamos tentar denovo?${NC}"
	sleep 2
	mainMenuScreen
    esac
  done
}

### New AMI screen
function newAmiScreen {
  clear
  printHeader "Criar nova versão AMI - ${IMAGE_NAME}"
  read -p "Digite o nome da versão: " -r  
  if [ -z "$REPLY" ]
    then
      echo -e "${RED}Você não digitou a versão!"
      echo -e "${ORANGE}Na duvida? Dê uma olhada na lista de versões disponíveis. "
      echo -e "Voltamos ao menu principal logo após os intervalos comerciais...${NC}"
      printSeparator 
      sleep 4
      return 1
  fi
  versionName="$REPLY"

  echo -n "Detectando o instance-id AWS... "
  INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id -s` 2> /dev/null
  if [ -z "$INSTANCE_ID" ]; then
      echo -e "${RED} [FALHOU]${NC}"
      printSeparator
      echo -e "${RED}Ooooops. Não foi possível detectar o instance-id aws." 
      echo -e "Essa é uma instância ec2?${NC}"
      echo -e "Em instantes voltamos com a nossa programacão normal...${NC}"
      printSeparator
      sleep 3
      return 2
  fi
  echo -e "${GREEN} [OK]${NC}"

  read -p "Será criada uma AMI com a versão '$versionName'. Confirma? [s/n] " -r
  printSeparator
  if [[ $REPLY =~ ^[Ss]$ ]]
  then
    echo -n "Enviando solicitacão de criacão da AMI... "
    jsonFile=/tmp/createAmiVersion`date +%s`.json
    aws ec2 create-image --instance-id "$INSTANCE_ID" --name "$IMAGE_NAME - $versionName" --no-reboot > $jsonFile
    if [ "$?" -ne 0 ] ; then
      echo -e "${RED} [FALHOU]${NC}"
      echo "Erro ao criar ami!! Abortando."
      printSeparator
      exit 3
    fi
    echo -e "${GREEN} [OK]${NC}"

    # Tags
    amiId=`cat $jsonFile | jq -r .ImageId`
    echo -n "Enviando solicitacão de criacão das TAGS... "
    aws ec2 create-tags --resources $amiId --tags Key=${CONTROL_TAG},Value=true Key=${VERSION_TAG},Value=$versionName
    if [ "$?" -ne 0 ] ; then
      echo -e "${RED} [FALHOU]${NC}"
      echo "Erro ao criar tags!! Abortando."
      printSeparator
      exit 4
    fi
    echo -e "${GREEN} [OK]${NC}"
    echo "Criacão da AMI deu rock'n roll! Pressione Enter para voltar."
    printSeparator
    read

  fi
}

### List AMI screen
function listAmiScreen {
  clear
  printHeader "Listagem e Gerenciamento de AMI's"
  echo -e "Escolha uma opcão:"
    echo -e " ${YELLOW}1)${NC} Atualizar a listagem"
    echo -e " ${YELLOW}2)${NC} Deletar Versão AMI" 
    echo -e " ${YELLOW}3)${NC} Fazer deploy de versão no Auto Scaling Group" 
    echo -e " ${YELLOW}0)${NC} Voltar"
    printSeparator
    keepAsking=1
    while [ $keepAsking -eq 1 ] ; do
      read -p "Opcão: " -r -n1
      echo
      keepAsking=0
      case "$REPLY" in
	1)
	  listAmiScreen
	  ;;
	2)
	  return 0
	  ;;
	3)
	  return 0
	  ;;
	0)
	  return 0
	  ;;
	*)
	  echo -e " ${RED}Ei! ${YELLOW} '${REPLY}' ${RED} não é opcão válida! Vamos tentar denovo?${NC}"
	  keepAsking=1
      esac
    done
}

## List AMI 'frame'
function listAmiFrame {
  json=`aws ec2 describe-images --filters Name=tag:${CONTROL_TAG},Values=true`
  amiIdList=`echo $json | jq -r '.[] | .[] | .ImageId'`
  versionList=`echo $json | jq -r ".[] | .[] | .Tags | .[] | if .Key == \"${VERSION_TAG}\"then .Value else \"\"  end | select(length > 0)"`
  finalList=`paste <(echo "$amiIdList") <(echo "$versionList") | sed 's/\t/ | /'`
  echo "   AMI ID    |  Tagged Version "
  echo "$finalList"
}


### Script excution begin
mainMenuScreen
