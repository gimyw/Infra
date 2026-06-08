# Farmily ECS Task 스펙 사이징 분석

## 1. 앱 특성 분석

| 항목 | 내용 |
| --- | --- |
| 프레임워크 | Spring Boot 4.0.6 / Java 21 |
| 주요 기능 | Bedrock 이미지 생성 (위주) + REST API |
| 온프레미스 서버 스펙 | vCPU 2, RAM 2GB (VMware VM) |
| 외부 연동 | Bedrock(이미지), S3, PostgreSQL, Redis, Kakao, PortOne, FCM |

### Bedrock 이미지 생성 앱의 워크로드 특성

- CPU: 거의 안 씀 (HTTP 요청을 Bedrock에 보내고 응답 대기)
- Memory: JVM 힙 + 요청/응답 버퍼 (이미지 Base64 응답이 크면 메모리 필요)
- I/O Wait: Bedrock 응답 대기 (수초~수십초), 스레드 점유
- **병목은 CPU가 아니라 동시 요청 수(스레드/메모리)**

---

## 2. ECS Task 스펙 추천

### Spring Boot + Bedrock 이미지 생성 기준

| 환경 | vCPU | Memory | Task 수 | 근거 |
| --- | --- | --- | --- | --- |
| Dev | 0.5 | 1GB | 1개 | JVM 단독이면 1GB 충분. 0.25/512MB는 Spring Boot에 빡빡함 |
| Prod (초기) | 1 | 2GB | 2개 | Bedrock 응답 대기 동안 메모리에 이미지 데이터 보관. 동시 요청 여유 확보 |
| Prod (스케일) | 1 | 2GB | 2~6개 (Auto Scaling) | 트래픽 예측 불가하므로 Auto Scaling 필수 |

### 현재 설정 vs 추천 설정 비교

| 비교 | 현재 (0.5vCPU / 1GB × 4) | 추천 (1vCPU / 2GB × 2) |
| --- | --- | --- |
| 총 비용 | ~$73/월 | ~$58/월 |
| JVM 여유 | 빡빡 (힙 512MB 제한) | 여유 (힙 1.2~1.5GB 가능) |
| Bedrock 응답 버퍼 | 이미지 Base64 크면 OOM 위험 | 안전 |
| 동시 처리 | Task당 동시 요청 적음 | Task당 더 많은 동시 요청 처리 |
| Auto Scaling | 4→6 확장 (비용 급증) | 2→4→6 단계적 확장 |

### JVM 설정 권장 (2GB Task 기준)

```
JAVA_OPTS=-Xms512m -Xmx1408m -XX:+UseG1GC -XX:MaxMetaspaceSize=128m
```

- Task 2GB 중 JVM 힙 1.4GB + Metaspace 128MB + OS/기타 ~400MB

---

## 3. 처리 용량 분석

### 현재 설정 (Prod: 0.5 vCPU / 1GB × 4 Task)

#### 일반 API 요청 (DB 조회, CRUD)

| 지표 | 예상치 |
| --- | --- |
| Task당 처리량 | ~50~100 req/s (응답 50~200ms 기준) |
| 4 Task 합산 | ~200~400 req/s |
| 동시 접속자 | ~500~1,000명 (사용자당 초당 0.3~0.5 요청 가정) |
| DAU 환산 | ~3,000~10,000명 (피크 집중률 10~30%) |

#### Bedrock 이미지 생성 요청

| 지표 | 예상치 |
| --- | --- |
| Bedrock 응답 시간 | 3~15초 (이미지 생성) |
| Task당 동시 처리 | ~10~20건 (Tomcat 스레드 200개 중 대기 점유) |
| 4 Task 합산 | 동시 40~80건 이미지 생성 |
| 분당 처리량 | ~200~400건/분 (평균 10초 가정) |

**한계점:** 동시에 80명 이상이 이미지 생성을 요청하면 스레드 고갈 → 응답 지연/타임아웃 발생

### 추천 설정 (1 vCPU / 2GB × 2 Task + Auto Scaling max 6)

#### 일반 API

| 지표 | min 2 Task | max 6 Task |
| --- | --- | --- |
| 처리량 | ~150~200 req/s | ~450~600 req/s |
| 동시 접속자 | ~400~700명 | ~1,200~2,000명 |

#### Bedrock 이미지 생성

| 지표 | min 2 Task | max 6 Task |
| --- | --- | --- |
| 동시 처리 | ~30~40건 | ~90~120건 |
| 분당 처리량 | ~150~250건 | ~450~700건 |

---

## 4. 실제 병목: Bedrock 서비스 쿼터

ECS 스펙보다 **Bedrock 계정별 동시 호출 제한(Throttle)**이 먼저 한계에 도달:

| 모델 | 기본 동시 호출 | 분당 요청 |
| --- | --- | --- |
| Stability AI (이미지) | ~5~10 동시 | ~50/분 |
| Titan Image Generator | ~5~10 동시 | ~50/분 |
| Claude (텍스트) | ~10~50 동시 | 더 넉넉 |

**ECS가 100건 동시 처리 가능해도 Bedrock이 10건만 받으면 나머지 90건은 큐잉/에러 발생**

### 대응 방안

| 방법 | 설명 |
| --- | --- |
| Bedrock 쿼터 증가 요청 | AWS Support를 통해 동시 호출 한도 상향 |
| SQS 큐잉 도입 | 이미지 생성 요청을 큐에 넣고 비동기 처리 |
| 사용자 UX | "생성 중..." 상태 표시 → 완료 시 알림 (비동기 패턴) |

---

## 5. 시나리오별 가능 여부

| 시나리오 | 현재 설정으로 가능? |
| --- | --- |
| DAU 1,000, 동시 100명 API | ✅ 여유 |
| DAU 5,000, 동시 500명 API | ✅ 가능 |
| 동시 이미지 생성 20건 | ✅ 가능 |
| 동시 이미지 생성 50건 | ⚠️ ECS는 OK, Bedrock Throttle 가능 |
| 동시 이미지 생성 100건+ | ❌ Bedrock 한도 초과 |

---

## 6. 최종 권장사항

| 항목 | 권장 |
| --- | --- |
| Prod 스펙 | 1 vCPU / 2GB / min 2 Task + Auto Scaling (max 6) |
| Dev 스펙 | 0.5 vCPU / 1GB / 1 Task |
| Scaling 기준 | CPU 70% 또는 동시 요청 수 기반 |
| 이미지 생성 | 비동기 처리 (SQS + 알림) 패턴 권장 |
| 모니터링 | CloudWatch CPU/Memory 메트릭으로 2주 운영 후 재조정 |
| 비용 | 현재 대비 월 ~$15 절감 + 안정성 향상 |

---

## 참고 레퍼런스

- [AWS Fargate Task Size 공식 문서](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size)
- [Right-sizing ECS Tasks](https://aws.amazon.com/blogs/containers/theoretical-cost-optimization-by-amazon-ecs-launch-type-fargate-vs-ec2/)
- [Amazon Bedrock Service Quotas](https://docs.aws.amazon.com/bedrock/latest/userguide/quotas.html)
- 실무 원칙: **작게 시작 → CloudWatch 메트릭 보고 조정** (CPU/Memory Utilization 70% 이하 유지)
