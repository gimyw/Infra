# gitops 기본 정책 — conftest(OPA). helm 렌더 결과(Deployment 등) 대상.
# 초기 soft 운영: Jenkinsfile.gitops가 `--no-fail`로 경고만. 신뢰 쌓이면 hard 전환.
package main

import rego.v1

# ── deny: resources.requests 필수 (노드 리소스 보장·과점유 방지) ──
# ⚠️ 현재 dev farmily-app은 resources 미지정 → 이 룰이 경고로 잡힘(의도된 가시화, soft라 비차단)
deny contains msg if {
	input.kind == "Deployment"
	some c in input.spec.template.spec.containers
	not c.resources.requests
	msg := sprintf("Deployment '%s' 컨테이너 '%s': resources.requests 누락", [input.metadata.name, c.name])
}

# ── deny: :latest 태그 금지 (불변 SHA 태그 원칙) ──
deny contains msg if {
	input.kind == "Deployment"
	some c in input.spec.template.spec.containers
	endswith(c.image, ":latest")
	msg := sprintf("Deployment '%s' 컨테이너 '%s': :latest 태그 금지(불변 SHA 태그 사용)", [input.metadata.name, c.name])
}

# ── warn: runAsNonRoot 권장 (root 컨테이너 지양) ──
warn contains msg if {
	input.kind == "Deployment"
	not input.spec.template.spec.securityContext.runAsNonRoot
	msg := sprintf("Deployment '%s': securityContext.runAsNonRoot 미설정(권장)", [input.metadata.name])
}
