#!groovy

def lambdas = [:]
def environments = [:]

pipeline {
    agent none
//    agent { label "shared" }
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }
    environment {
        s3SubFolder = "RDS/Code"
    }
    stages {
        stage("Prepare Pipeline") {
            agent { label "shared" }
            steps {
                script {
                    env.GIT_URL = sh(returnStdout: true, script: 'git config remote.origin.url').trim()
                    pipelinePrepare()

                    lambdas.put("shipRdsLogsToS3", [
                            localDir : "shipRdsLogsToS3",
                            extension: "*.py",
                            language : "python",
                            zipfile  : "Rds_to_S3-${env.GIT_COMMIT}.zip",
                            stashName: "shipRdsLogsToS3"])
                    lambdas.put("transformRdsLogsToES", [
                            localDir : "transformRdsLogsToES",
                            zipfile  : "s3-to-es-${env.GIT_COMMIT}.zip",
                            language : "node",
                            extension: "*.js",
                            stashName: "transformRdsLogsToES"])
                    environments.put("devl", [s3Bucket: "rds-logs-aggregation-devl"])
                    environments.put("prod", [s3Bucket: "rds-logs-aggregation-prod"])
                    environments.put("shared", [s3Bucket: "rds-logs-aggregation-shared"])
                }
            }
        }
        stage("Run unit tests") {
            agent { label "shared" }
            steps {
                dir("lambda/transformRdsLogsToES") {
                    sh("docker run --rm -v \$PWD:/app -w /app node:6.10 npm install > npminstall.log")
                    sh("docker run --rm -v \$PWD:/app -w /app node:6.10 npm test")
                }
                step([$class: 'WsCleanup'])
            }
        }
        stage("Build lambda code") {
            agent { label "shared" }
            when { branch 'vk28594' }
            steps {
                checkout scm
                script {
                    dir("lambda/transformRdsLogsToES") {
                        sh("docker run --rm -v \$PWD:/app -w /app node:6.10 npm install --only=production > npminstall.log")
                    }

                    lambdas.each {
                        echo "Building lambda ${it.key}"
                        dir("lambda/${it.value.localDir}") {
                            if (it.value.language == "node") {
                                sh "zip ${it.value.zipfile} -r node_modules"
                                dir("src") {
                                    sh "zip -u ../${it.value.zipfile} ${it.value.extension}"
                                }
                            } else {
                                sh "zip ${it.value.zipfile} ${it.value.extension}"
                            }

                            stash name: "${it.value.stashName}", includes: "${it.value.zipfile}"
                        }
                    }
                }
            }
        }


        stage("Upload deployment packages") {
            agent { label "shared" }
            when { branch 'vk28594' }
            steps {
                script {
                    def parallelSteps = [:]
                    environments.each { environment ->
                        parallelSteps.put(environment.key, {
                            node(environment.key) {
                                lambdas.each { lambda ->
                                    echo "Uploading lambda ${lambda.key}"
                                    unstash name: "${lambda.value.stashName}"
                                   awsS3Upload(environment.value.s3Bucket, s3SubFolder, lambda.value.zipfile, lambda.value.zipfile)
                                }
                            }
                        })
                    }
                    parallel parallelSteps
                }
            }
        }

        stage("Run RdsLogShipper Terraform") {
            agent { label "shared" }
            when { branch 'vk28594' }
            steps {
                script {
                    def parallelSteps = [:]
                    environments.each {
                        parallelSteps.put(it.key, {
                            echo "Running for ${it.key}"

                            def tfParameters = "-var-file=${it.key} -var git_url=${env.GIT_URL}, -var git_commit=${env.GIT_COMMIT} -var s3_bucket=${it.value.s3Bucket} -var s3_path=${s3SubFolder}"
                            terraformPlanAndApply(it.key, "latest", tfParameters)
                        })
                    }
                    parallel parallelSteps
                }
            }
        }
    }
}

def terraformPlanAndApply(String environment, String terraformVersion, tfParameters = "") {
    stage("Terraform ${environment}") {
        node(environment) {
            step([$class: 'WsCleanup'])
            checkout scm

            String terraformDockerCommand = "docker run -v `pwd`:`pwd` -w `pwd` 689019322137.dkr.ecr.us-east-1.amazonaws.com/terraform:${terraformVersion}"
            String terraformOptions = "-no-color"

            dir("terraform/transformRdslogsToES") {
                    sh "aws ecr get-login --registry-ids 689019322137 --no-include-email --region us-east-1 > ecr_login && chmod +x ecr_login && ./ecr_login"
                    sh "${terraformDockerCommand} init ${terraformOptions} -input=false"
                    sh "${terraformDockerCommand} workspace select ${environment} ${terraformOptions} || ${terraformDockerCommand} workspace new ${environment} ${terraformOptions}"
                    def output = sh(script: "${terraformDockerCommand} plan --out tfplan ${terraformOptions} ${tfParameters}", returnStdout: true)
                    echo output
                    if (output.contains("No changes")) {
                        echo "No changes are detected, skipping 'tf apply'"
                    } else {
                        sh "${terraformDockerCommand} apply tfplan ${terraformOptions}"
                    }
                    sh "docker run -v `pwd`:`pwd` -w `pwd` -e jdf_env=${environment} 689019322137.dkr.ecr.us-east-1.amazonaws.com/awspec:latest"
            }
        }
    }
}


