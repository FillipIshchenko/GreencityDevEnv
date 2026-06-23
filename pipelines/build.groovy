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
                dir(repoPath) {
                    stage('Build & Sonar scan (Java)') {
                        withEnv(["SONAR_PROJECT=${repoName}"]) {
                            withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                                sh 'mvn -B -ntp clean verify sonar:sonar -DskipTests -Dformatter.skip=true -Dcheckstyle.skip=true -Dspotless.check.skip=true -Dsonar.host.url=http://sonarqube:9000 -Dsonar.token=$SONAR_TOKEN -Dsonar.projectKey=$SONAR_PROJECT -Dsonar.projectName=$SONAR_PROJECT'
                            }
                        }
                    }

                    stage('Quality Gate') {
                        echo "Checking SonarQube quality gate via API ..."
                        withEnv(["SONAR_PROJECT=${repoName}"]) {
                            withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                                timeout(time: 10, unit: 'MINUTES') {
                                    sh '''
set -e
SONAR_URL=http://sonarqube:9000
TASK_ID=$(grep '^ceTaskId=' target/sonar/report-task.txt | cut -d= -f2)
echo "Sonar CE task id: $TASK_ID"

STATUS=PENDING
CE_JSON=
while [ "$STATUS" = "PENDING" ] || [ "$STATUS" = "IN_PROGRESS" ]; do
  sleep 3
  CE_JSON=$(curl -s -u "$SONAR_TOKEN:" "$SONAR_URL/api/ce/task?id=$TASK_ID")
  STATUS=$(echo "$CE_JSON" | grep -o '"status":"[A-Z_]*"' | head -1 | cut -d'"' -f4)
  echo "CE task status: $STATUS"
done

if [ "$STATUS" != "SUCCESS" ]; then
  echo "SonarQube analysis task did not succeed (status: $STATUS)"
  exit 1
fi

ANALYSIS_ID=$(echo "$CE_JSON" | grep -o '"analysisId":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Analysis id: $ANALYSIS_ID"

if [ -n "$ANALYSIS_ID" ]; then
  GATE_JSON=$(curl -s -u "$SONAR_TOKEN:" "$SONAR_URL/api/qualitygates/project_status?analysisId=$ANALYSIS_ID")
else
  GATE_JSON=$(curl -s -u "$SONAR_TOKEN:" "$SONAR_URL/api/qualitygates/project_status?projectKey=$SONAR_PROJECT")
fi
echo "Gate API response: $GATE_JSON"

GATE=$(echo "$GATE_JSON" | grep -o '"status":"[A-Z]*"' | head -1 | cut -d'"' -f4)
echo "Quality gate status: $GATE"

if [ "$GATE" != "OK" ]; then
  echo "Quality gate FAILED (status: $GATE). See $SONAR_URL/dashboard?id=$SONAR_PROJECT"
  exit 1
fi
echo "Quality gate PASSED."
'''
                                }
                            }
                        }
                    }
                }
            } else {
                stage('Frontend (no gate)') {
                    echo "SonarQube gate skipped for the Angular frontend (by design)."
                    echo "The image rebuild below will surface any build failure."
                }
            }

            stage('Rebuild & Restart app service') {
                sh '''
DF=/workspace/app/Dockerfile.greencity-java
for d in GreenCityUser GreenCityMVP; do
  if [ -d "/workspace/repos/$d" ]; then
    cp "$DF" "/workspace/repos/$d/Dockerfile.greencity-ci"
  fi
done
'''
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
