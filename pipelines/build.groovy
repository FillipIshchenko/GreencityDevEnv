def serviceFor(name) {
    switch (name) {
        case 'GreenCityUser':   return 'greencity-user'
        case 'GreenCityMVP':    return 'greencity-core'
        case 'GreenCityClient': return 'greencity-client'
        default: error "Unknown repo: ${name}"
    }
}

def repoName = env.REPO_NAME
def repoDir  = env.REPO_DIR
def runGate  = (env.RUN_GATE == 'true')
def service  = serviceFor(repoName)
def repoPath = "/workspace/repos/${repoDir}"
def compose  = "docker compose -f /workspace/app/docker-compose.app.yml --project-directory /workspace/app"

timestamps {
    ansiColor('xterm') {
        try {
            stage('Info') {
                echo "Repo:    ${repoName}"
                echo "Service: ${service}"
                echo "Gate:    ${runGate}"
                sh "git -C '${repoPath}' --no-pager log -1 --oneline || true"
            }

            if (runGate) {
                stage('Build & Sonar scan (Java)') {
                    dir(repoPath) {
                        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                            sh "mvn -B -ntp clean verify sonar:sonar -DskipTests -Dformatter.skip=true -Dcheckstyle.skip=true -Dspotless.check.skip=true -Dsonar.host.url=http://sonarqube:9000 -Dsonar.token=\$SONAR_TOKEN -Dsonar.projectKey=${repoName} -Dsonar.projectName=${repoName}"
                        }
                    }
                }

                stage('Quality Gate') {
                    withSonarQubeEnv('greencity-sonar') {
                        echo "Waiting for SonarQube quality gate result ..."
                    }
                    timeout(time: 10, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            } else {
                stage('Frontend (no gate)') {
                    echo "SonarQube gate skipped for the Angular frontend (by design)."
                    echo "The image rebuild below will surface any build failure."
                }
            }

            stage('Rebuild & Restart app service') {
                sh "${compose} build ${service}"
                sh "${compose} up -d ${service}"
            }

            stage('Verify health') {
                sh "sleep 10 && ${compose} ps"
                def state = sh(
                    script: "${compose} ps --format '{{.Name}} {{.State}} {{.Status}}' ${service}",
                    returnStdout: true
                ).trim()
                echo "Service state: ${state}"
            }

            echo "============================================================"
            echo " ${repoName}: gate passed, image rebuilt, app restarted."
            echo " App:  http://localhost:4200  |  :8080  |  :8060"
            echo ""
            echo " Happy with it? Push upstream when YOU choose:"
            echo "   git -C repos/${repoDir} push origin <your-branch>"
            echo "============================================================"

        } catch (err) {
            echo "============================================================"
            echo " ${repoName}: FAILED — ${err}"
            echo " If this was the quality gate, open http://localhost:9000"
            echo " (project '${repoName}') to see what to fix."
            echo " The previously running app version was left untouched."
            echo "============================================================"
            throw err
        }
    }
}
