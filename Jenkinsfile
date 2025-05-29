pipeline {
    agent {
        kubernetes {
            inheritFrom 'my-jenkins-jenkins-agent'
            defaultContainer 'jnlp'
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins-build: app-build
spec:
  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.5.1-debug
      imagePullPolicy: IfNotPresent
      command:
        - /busybox/cat
      tty: true
      volumeMounts:
        - name: jenkins-docker-cfg
          mountPath: /kaniko/.docker

    - name: trivy
      image: aquasec/trivy:latest
      command:
        - cat
      tty: true

  tolerations:
    - key: "gpu"
      operator: "Equal"
      value: "missing"
      effect: "NoSchedule"

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "gpu"
                operator: In
                values:
                  - "missing"

  nodeSelector:
    gpu: missing

  volumes:
    - name: jenkins-docker-cfg
      projected:
        sources:
          - secret:
              name: docker-credentials
              items:
                - key: .dockerconfigjson
                  path: config.json
"""
        }
    }

    environment {
        APP_COMMIT = ''
        DOCKER_IMAGE = '992382633140.dkr.ecr.us-east-1.amazonaws.com/argo'
        TRIVY_SEVERITY = 'CRITICAL'
        TRIVY_EXIT_CODE = '1'
        TRIVY_FORMAT = 'json'
        TRIVY_TIMEOUT = '5m'
    }

    stages {
        stage('Capture App Commit') {
            steps {
                script {
                    def appCommit = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.APP_COMMIT = appCommit
                    echo "Captured App Commit: ${env.APP_COMMIT}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                container(name: 'kaniko', shell: '/busybox/sh') {
                    withEnv(['PATH+EXTRA=/busybox']) {
                        sh '''#!/busybox/sh -xe
                        /kaniko/executor \
                            --dockerfile Dockerfile \
                            --context `pwd`/ \
                            --verbosity debug \
                            --insecure \
                            --skip-tls-verify \
                            --destination ${DOCKER_IMAGE}:${BUILD_NUMBER}
                        '''
                    }
                }
            }
        }

        stage('Scan Docker Image') {
            steps {
                container('trivy') {
                    script {
                        try {
                            sh """
                            trivy image --severity CRITICAL,HIGH,MEDIUM,LOW \
                                      --format ${TRIVY_FORMAT} \
                                      --timeout ${TRIVY_TIMEOUT} \
                                      --output trivy-full-report.json \
                                      ${DOCKER_IMAGE}:${BUILD_NUMBER}
                            """
                            
                            sh """
                            trivy image --severity ${TRIVY_SEVERITY} \
                                      --exit-code ${TRIVY_EXIT_CODE} \
                                      --format ${TRIVY_FORMAT} \
                                      --timeout ${TRIVY_TIMEOUT} \
                                      --output trivy-results.json \
                                      ${DOCKER_IMAGE}:${BUILD_NUMBER}
                            """
                            
                            archiveArtifacts artifacts: 'trivy-*-report.json', allowEmptyArchive: true
                            
                        } catch (Exception e) {
                            echo "Critical vulnerabilities found in the Docker image!"
                            
                            def fullReport = readFile('trivy-full-report.json')
                            echo "Full vulnerability report:"
                            echo fullReport
                            
                            def criticalReport = readFile('trivy-results.json')
                            echo "\nCritical vulnerabilities that caused the failure:"
                            echo criticalReport
                            
                            archiveArtifacts artifacts: 'trivy-*-report.json', allowEmptyArchive: true
                            
                            def errorMsg = """
                            Docker image scan failed due to critical vulnerabilities.
                            Please check the archived Trivy reports for details:
                            - trivy-full-report.json: Contains all vulnerabilities
                            - trivy-results.json: Contains critical vulnerabilities
                            
                            To fix these issues:
                            1. Review the vulnerabilities in the reports
                            2. Update your Dockerfile to use a more recent base image
                            3. Remove unnecessary packages
                            4. Update any outdated packages
                            """
                            
                            currentBuild.result = 'FAILURE'
                            error(errorMsg)
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                if (fileExists('trivy-*-report.json')) {
                    archiveArtifacts artifacts: 'trivy-*-report.json', allowEmptyArchive: true
                }
            }
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed! Check the archived Trivy reports for vulnerability details.'
            echo 'The reports are available in the Jenkins build artifacts.'
        }
    }
}
