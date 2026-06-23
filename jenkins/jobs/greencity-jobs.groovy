def repos = [
    [name: 'GreenCityUser',   dir: 'GreenCityUser',   gate: true ],
    [name: 'GreenCityMVP',    dir: 'GreenCityMVP',    gate: true ],
    [name: 'GreenCityClient', dir: 'GreenCityClient', gate: false],
]

repos.each { repo ->
    pipelineJob("build-${repo.name}") {
        description("""
            Builds <b>${repo.name}</b> from the local working clone, runs the
            SonarQube quality gate ${repo.gate ? '(ENABLED)' : '(skipped - frontend)'},
            and on success rebuilds + restarts the app stack.
            Triggered when you <code>git commit</code> in repos/${repo.dir}.
        """.stripIndent())

        triggers {
            scm('* * * * *')
        }

        definition {
            cps {
                sandbox(true)
                script("""
                    properties([
                        pipelineTriggers([pollSCM('* * * * *')])
                    ])
                    node {
                        env.REPO_NAME = '${repo.name}'
                        env.REPO_DIR  = '${repo.dir}'
                        env.RUN_GATE  = '${repo.gate}'

                        stage('Checkout working clone') {
                            checkout([
                                \$class: 'GitSCM',
                                branches: [[name: '**']],
                                userRemoteConfigs: [[url: 'file:///workspace/repos/${repo.dir}']],
                                extensions: [[\$class: 'LocalBranch', localBranch: '**']]
                            ])
                        }
                        load '/workspace/pipelines/build.groovy'
                    }
                """.stripIndent())
            }
        }
    }
}

pipelineJob('upstream-notify') {
    description('''
        Every 5 minutes, fetches upstream (origin) for all three repos and
        reports which have new commits available. Does not pull.
        Status is written to repos/.upstream-status. See scripts/check-upstream.sh.
    ''')
    triggers {
        cron('H/5 * * * *')
    }
    definition {
        cps {
            sandbox(true)
            script('''
                node {
                    stage('Check upstream') {
                        sh 'bash /workspace/scripts/check-upstream.sh'
                        sh 'cat /workspace/repos/.upstream-status || true'
                    }
                }
            '''.stripIndent())
        }
    }
}
