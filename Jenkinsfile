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
        TRIVY_SEVERITY = 'CRITICAL,HIGH'
        TRIVY_EXIT_CODE = '1'
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
                            trivy image --severity ${TRIVY_SEVERITY} \
                                      --exit-code ${TRIVY_EXIT_CODE} \
                                      --format table \
                                      --output trivy-results.txt \
                                      ${DOCKER_IMAGE}:${BUILD_NUMBER}
                            """
                        } catch (Exception e) {
                            echo "Critical or High severity vulnerabilities found!"
                            sh 'cat trivy-results.txt'
                            currentBuild.result = 'FAILURE'
                            error('Docker image scan failed due to critical/high vulnerabilities')
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                if (fileExists('trivy-results.txt')) {
                    archiveArtifacts artifacts: 'trivy-results.txt', allowEmptyArchive: true
                }
            }
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed! Check the logs for details.'
        }
    }
} 
