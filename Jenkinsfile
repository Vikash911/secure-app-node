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
      volumeMounts:
        - name: jenkins-docker-cfg
          mountPath: /root/.docker

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
        TRIVY_FORMAT = 'table'
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

        stage('Verify Image Access') {
            steps {
                container('trivy') {
                    script {
                        try {
                            // Verify Docker credentials
                            sh 'ls -la /root/.docker/'
                            
                            // Try to pull the image to verify access
                            sh """
                            docker pull ${DOCKER_IMAGE}:${BUILD_NUMBER} || {
                                echo "Failed to pull image. Checking Docker configuration..."
                                cat /root/.docker/config.json
                                exit 1
                            }
                            """
                            
                            // List available images
                            sh 'docker images'
                            
                        } catch (Exception e) {
                            echo "Error verifying image access: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error """
                            Failed to verify Docker image access!
                            Error: ${e.message}
                            
                            Please check:
                            1. Docker credentials are properly configured
                            2. The image was successfully pushed
                            3. The Trivy container has proper permissions
                            """
                        }
                    }
                }
            }
        }

        stage('Scan Docker Image') {
            steps {
                container('trivy') {
                    script {
                        try {
                            // First, try to list the image
                            sh """
                            echo "Available images:"
                            docker images | grep ${DOCKER_IMAGE}
                            """
                            
                            // Run Trivy scan with debug output
                            def scanOutput = sh(
                                script: """
                                trivy image --debug \
                                          --severity ${TRIVY_SEVERITY} \
                                          --format ${TRIVY_FORMAT} \
                                          --timeout ${TRIVY_TIMEOUT} \
                                          ${DOCKER_IMAGE}:${BUILD_NUMBER}
                                """,
                                returnStdout: true
                            ).trim()
                            
                            writeFile file: 'trivy-results.txt', text: scanOutput
                            
                            // Run full scan for reference
                            def fullScanOutput = sh(
                                script: """
                                trivy image --debug \
                                          --severity CRITICAL,HIGH,MEDIUM,LOW \
                                          --format ${TRIVY_FORMAT} \
                                          --timeout ${TRIVY_TIMEOUT} \
                                          ${DOCKER_IMAGE}:${BUILD_NUMBER}
                                """,
                                returnStdout: true
                            ).trim()
                            
                            writeFile file: 'trivy-full-report.txt', text: fullScanOutput
                            
                            archiveArtifacts artifacts: 'trivy-*-report.txt', allowEmptyArchive: true
                            
                            if (scanOutput.contains('CRITICAL')) {
                                error """
                                Critical vulnerabilities found in the Docker image!
                                
                                Full vulnerability report:
                                ${fullScanOutput}
                                
                                Critical vulnerabilities that caused the failure:
                                ${scanOutput}
                                
                                To fix these issues:
                                1. Review the vulnerabilities in the reports
                                2. Update your Dockerfile to use a more recent base image
                                3. Remove unnecessary packages
                                4. Update any outdated packages
                                """
                            }
                            
                        } catch (Exception e) {
                            echo "Error during Trivy scan: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error """
                            Docker image scan failed!
                            Error: ${e.message}
                            
                            Please check:
                            1. The Docker image was built successfully
                            2. The image is accessible to Trivy
                            3. The Trivy container has proper permissions
                            4. Docker credentials are properly configured
                            """
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                if (fileExists('trivy-*-report.txt')) {
                    archiveArtifacts artifacts: 'trivy-*-report.txt', allowEmptyArchive: true
                }
            }
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed! Check the build logs and archived Trivy reports for details.'
        }
    }
}
