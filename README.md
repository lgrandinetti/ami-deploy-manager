# ami-deploy-manager

## Objetivo

Este script tem por objetivo gerenciar de maneira versionada e fazendo uso de tags AWS, imagens AMI no
ambiente Amazon AWS.

As funções atualmente disponíveis no script são:

* Criação de nova AMI versionada utilizando como base a pŕopria máquina onde o script está sendo executado.
* Listagem e deleção de AMI's criadas anteriormente pelo script.
* Efetuar deploy de AMI selecionda no Auto Scaling Group previamente configurado no script.

A interface do script é auto explicativa e faz uso de menus interativos com seleção numérica das opções, 
não necessitando portanto, de nenhum parâmetro adicional em linha decomando.

## Dependências

Os seguintes comandos precisam estar disponíveis no PATH para que o script funcionde de maneira correta:

* aws - Disponível no pacote AWS Cli. Pode ser baixado diretamente da amazon, via pip ou package manager no ubuntu (apt) / amazon linux (yum). Link: https://aws.amazon.com/pt/cli/
* curl - Normalmente já vem instalado na maioria das distribuições.
* jq - Utilitário para parsing de json, disponível via package manager (apt ou yum)
* aws-ha-release (Deploy auto-scaling-group) - Scrit que é parte do 'aws-missing-tools'. 
	Pode ser baixado diretamente do githubo do projeto em: https://github.com/colinbjohnson/aws-missing-tools/tree/master/aws-ha-release

## Configuração

O Script contém as seguintes variáveis sendo definidas em seu início que devem ser preenchidas de acordo com o desejado:

```sh
export IMAGE_NAME=""                # Nome que será utilizado como prefixo para todas AMI's criadas
export CONTROL_TAG=""               # Nome da TAG que será utilizada para identificar as AMI's gerenciadas pelo script
export VERSION_TAG=""               # Nome da TAG que será utilizada para armazenar a versão da AMI
export AUTO_SCALING_GROUP_NAME=""   # Nome do auto scaling group utilizado nas funções de deploy
export AUTO_SCALING_GROUP_REGION="" # Região onde o auto scaling group está configurado
export AWS_HA_RELEASE=""            # Path do script aws-ha-release para o deploy no auto scaling group
```
Além dessas variáveis, o aws cli deverá estar configurado (aws configure) com as credenciais de uma conta com as permissões de acordo com a seguinte policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1447180337000",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeRegions",
                "ec2:DescribeInstances",
                "ec2:DescribeVolumes",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot",
                "ec2:DescribeSnapshotAttribute",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:DescribeTags",
                "ec2:CreateImage",
                "ec2:DescribeImages",
                "ec2:DescribeImageAttribute",
                "ec2:DeregisterImage",
                "ec2:CreateTags",
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:SuspendProcesses",
                "autoscaling:UpdateAutoScalingGroup",
                "elasticloadbalancing:DescribeInstanceHealth",
                "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "autoscaling:ResumeProcesses",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:CreateLaunchConfiguration",
                "autoscaling:DeleteLaunchConfiguration",
                "autoscaling:UpdateAutoScalingGroup"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```

