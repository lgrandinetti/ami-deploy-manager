#!/bin/bash

####  Main configurations
export IMAGE_NAME=""
export CONTROL_TAG=""
export VERSION_TAG=""
export AUTO_SCALING_GROUP_NAME=""
export AUTO_SCALING_GROUP_REGION="sa-east-1"
export AWS_HA_RELEASE="../aws-missing-tools/aws-ha-release/aws-ha-release.sh"

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
    echo -e " ${YELLOW}2)${NC} Deletar Versão AMI" 
    echo -e " ${YELLOW}3)${NC} Modificar versão AMI do Auto Scaling Group"
    echo -e " ${YELLOW}4)${NC} Forçar atualização das instancias do Auto Scaling Group" 
    echo -e " ${YELLOW}0)${NC} Sair" 
    printSeparator
    read -p "Opcão: " -r -n1
    echo
      
    case "$REPLY" in
      1)
	newAmiScreen
	;;
      2)
	deleteAmiScreen
	;;
      3)
	updateLaunchConfigurationScreen
	;;
      4)
	awsHaReleaseScreen
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
      echo -e "${CYAN}Na duvida? Dê uma olhada na lista de versões disponíveis. "
      echo -e "Voltamos ao menu principal logo após os intervalos comerciais...${NC}"
      printSeparator 
      sleep 5
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

  echo -e "Será criada uma AMI com a versão ${YELLOW}'$versionName'.${NC}"
  read -p "Confirma? [s/n] " -r
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
    echo -e "Criacão da AMI deu rock'n roll! Pressione ${CYAN}Enter${NC} para voltar."
    printSeparator
    read

  fi
}

### Delete AMI screen
function deleteAmiScreen {
  clear
  printHeader "DELECÃO DE IMAGEM AMI"
  listAmiFrame
  
  printSeparator
  
  echo -e "Digite o ID da imagem a ser ${RED}DELETADA${NC} ou enter para volar:"
    
    read -p "AMI ID: "
    printSeparator
    if [ -z "$REPLY" ] ; then
      return
    fi
    
    ## Queries AMI information and get EBS volume ID
    echo -n "Consultando dados da Imagem..."
    snapshotId=`aws ec2 describe-images --image-ids "$REPLY" | jq -r '.[] | .[] | .BlockDeviceMappings | .[] | .Ebs | .SnapshotId'`
    if [ "$?" -ne 0 ] ; then
      echo -e "${RED} [FALHOU]${NC}"
      echo "Erro ao consultar dados da AMI. Abortando."
      printSeparator
      exit 4
    fi
    echo -e "${GREEN} [OK]${NC}"
    
    ## Deregister AMI
    echo -n "Enviando request para desregistro da AMI: ${REPLY})..."
    aws ec2 deregister-image --image-id "$REPLY"
    if [ "$?" -ne 0 ] ; then
      echo -e "${RED} [FALHOU]${NC}"
      echo "Erro ao tentar desregistrar AMI ${REPLY}. Abortando."
      printSeparator
      exit 4
    fi
    echo -e "${GREEN} [OK]${NC}"
    
    ## Delete EBS snapshot
    echo -n "Enviando request de delecão do Snapshot EBS (ID: ${snapshotId})..."
    aws ec2 delete-snapshot --snapshot-id ${snapshotId}
    if [ "$?" -ne 0 ] ; then
      echo -e "${RED} [FALHOU]${NC}"
      echo "Erro ao tentar remover Snapshot EBS ${snapshotId}. Abortando."
      printSeparator
      exit 4
    fi
    echo -e "${GREEN} [OK]${NC}"
    echo -e "AMI Deletada! Pressione ${CYAN}Enter${NC} para voltar."
    read
}

### Delete AMI screen
function updateLaunchConfigurationScreen {
  clear
  printHeader "ALTERAÇÃO DA VERSÃO AMI NO AUTO SCALING GROUP"
  
  ## Queries Auto Scaling group for current launch configuration name
  echo -n "Consultando dados do auto scaling group '${AUTO_SCALING_GROUP_NAME}'"
  currentLaunchConfigurationName=`aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name "${AUTO_SCALING_GROUP_NAME}" | jq -r '.AutoScalingGroups | .[] | .LaunchConfigurationName'`
  checkError $?
  
  ## Queries for current launch configuration data
  echo -n "Consultando dados do launch configuration '${currentLaunchConfigurationName}'"
  currentLaunchConfigurationJson=`aws autoscaling describe-launch-configurations --launch-configuration-names "${currentLaunchConfigurationName}"`
  checkError $?
  
  currentAmi=`echo $currentLaunchConfigurationJson | jq -r '.LaunchConfigurations | .[0] | .ImageId'`
  instanceType=`echo $currentLaunchConfigurationJson | jq -r '.LaunchConfigurations | .[0] | .InstanceType'`
  securityGroup=`echo $currentLaunchConfigurationJson | jq -r '.LaunchConfigurations | .[0] | .SecurityGroups | .[0]'`
  keyName=`echo $currentLaunchConfigurationJson | jq -r '.LaunchConfigurations | .[0] | .KeyName'`
  
  listAmiFrame $currentAmi
  printSeparator
  
  echo -e "Digite o ID da imagem a ser Substituída no Auto Scaling Group ou enter para voltar:"  
  read -p "AMI ID: "
  if [ -z "$REPLY" ] ; then
    return
  fi
  newAmiId=$REPLY
  
  if [ "$newAmiId" = "$currentAmi" ] ; then
    echo -e "${RED}Eeeiii!!! ${YELLOW}Você digitou o id da AMI que já está ativo no Auto Scaling Group."
    echo -e "${CYAN}Que tal lavar o rosto e pegar um café enquanto eu volto para o menu principal?${NC}"
    sleep 8
    return
  fi
    
  ## Queries for AMI version
  echo -n "Consultando dados da Imagem..."
  newAmiVersion=`aws ec2 describe-images --image-ids "$newAmiId" | jq -r ".Images | .[0] | .Tags | .[] | if .Key == \"${VERSION_TAG}\"then .Value else \"\"  end | select(length > 0)"`
  newLaunchConfigurationName="${AUTO_SCALING_GROUP_NAME}-${newAmiVersion}"
  checkError $?
  
  printSeparator
  echo "Novo launch config:"
  echo -e "Nome:           ${CYAN}${newLaunchConfigurationName}${NC}"
  echo -e "Ami:            ${CYAN}${newAmiId}${NC}"
  echo -e "Versão:         ${CYAN}${newAmiVersion}${NC}"
  echo -e "Instance Type:  ${CYAN}${instanceType}${NC}"
  echo -e "Key:            ${CYAN}${keyName}${NC}"
  echo -e "Security Group: ${CYAN}${securityGroup}${NC}"
  read -p "Confirma? [s/n] " -r
  printSeparator
  if [[ $REPLY =~ ^[Ss]$ ]] ; then 
    # Create new launch configuration
    echo -n "Criando novo launch configuration..."
    aws autoscaling create-launch-configuration --launch-configuration-name "${newLaunchConfigurationName}" --key-name ${keyName} --security-groups ${securityGroup} --instance-type ${instanceType} --image-id ${newAmiId}
    checkError $?
  
    echo -n "Substituindo launch configuration no Auto Scaling Group..."
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name "${AUTO_SCALING_GROUP_NAME}" --launch-configuration-name "${newLaunchConfigurationName}"
    checkError $?
    
    
    echo -n "Deletando antigo launch configuration (${currentLaunchConfigurationName})..."
    aws autoscaling delete-launch-configuration --launch-configuration-name "${currentLaunchConfigurationName}"
    checkError $?
    
    printSeparator
    
    read -p "Auto Scaling Group atualizado com a AMI selecionada. Deseja forcar o reload das instancias? [s/n] " -r
    if [[ $REPLY =~ ^[Ss]$ ]] ; then 
      callAwsHaRelease
      checkError $?
      echo -e "Update de versão finalizado! Pressione ${CYAN}Enter${NC} para voltar."
      read
    fi
  fi
}

## AwsHaReleaseScreen
function awsHaReleaseScreen {
  clear
  printHeader "FORCAR RELOAD DAS INSTANCIAS NO AUTO SCALING GROUP"
  read -p "Tem certeza? [s/n] " -r
    if [[ $REPLY =~ ^[Ss]$ ]] ; then 
      callAwsHaRelease
      checkError $?
      echo -e "Reload finalizado! Pressione ${CYAN}Enter${NC} para voltar."
      read
    fi
}

## List AMI 'frame'
function listAmiFrame {
  echo -n "Carregando listagem..."
  json=`aws ec2 describe-images --filters Name=tag:${CONTROL_TAG},Values=true`
  checkError $?
  printSeparator
  amiIdList=`echo $json | jq -r '.[] | .[] | .ImageId' | sed 's/^/  /g'` # Last sed just adds two empty spaces to the beginning
  versionList=`echo $json | jq -r ".[] | .[] | .Tags | .[] | if .Key == \"${VERSION_TAG}\"then .Value else \"\"  end | select(length > 0)"`
  if [ -z "$1" ] ; then
    finalList=`paste <(echo "$amiIdList") <(echo "$versionList") | sed 's/\t/ | /'`
  else
    finalList=`paste <(echo "$amiIdList") <(echo "$versionList") | sed "s/  ${1}/* ${1}/" |sed 's/\t/ | /'`
  fi
  echo -e "${ORANGE}    AMI ID     | Versão ${NC}"
  echo -e "${YELLOW}${finalList}${NC}"
  if [ -n "$1" ] ; then
    echo
    echo -e "${CYAN}* indica a imagem atualmente configurada no Auto Scaling group ${NC}"
  fi  
}

function callAwsHaRelease
{
  printSeparator
  echo "Executando:"
  echo $AWS_HA_RELEASE -a "${AUTO_SCALING_GROUP_NAME}" -r ${AUTO_SCALING_GROUP_REGION}
  echo
  $AWS_HA_RELEASE -a "${AUTO_SCALING_GROUP_NAME}" -r ${AUTO_SCALING_GROUP_REGION}
  printSeparator
  return $?
}

function checkError {
  if [ "$1" -ne 0 ] ; then
    echo -e "${RED} [FALHOU]${NC}"
    echo "Erro na chamada do comando. Abortando."
    printSeparator
    exit 4
  fi
  echo -e "${GREEN} [OK]${NC}"
}


### Script excution begin
mainMenuScreen