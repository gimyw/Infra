resource "aws_iam_role_policy_attachment" "cluster_policy" {
   role = aws_iam_role.cluster.name
   # EKS 컨트롤플레인이 필요로 하는 역할 AWS 표준
   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  //dev면 dev-eks, prod면 prod-eks
  name     = "${var.env}-eks"
  //k8s 버전
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = concat(var.private_subnet_ids,var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
  }
  //kubectl 권한
  access_config {
    //API 인증 방식 사용
    authentication_mode                         = "API_AND_CONFIG_MAP"
    //이걸 만든 IAM 주체에서 해당 클러스터에 자동으로 Admin으로 등록한다.
    bootstrap_cluster_creator_admin_permissions = true
  }
  //권한 부착이 완료된 뒤 클러스터를 만들라고 명령
  depends_on = [ aws_iam_role_policy_attachment.cluster_policy ]
  tags = { Name = "${var.env}-eks"}
}

//리소스를 만드는게 아닌 불러옴
data "tls_certificate" "oidc"{
    url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
//IRSA의 토대 즉 쿠버네티스 파드가 AWS에 접근할 수 있는 IAM ROLE을 직접 맡을 수 있는가 
//(즉 접근권한이 있는가?)
resource "aws_iam_openid_connect_provider" "this" {
    url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
    client_id_list  = ["sts.amazonaws.com"] 
    thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

    tags = {Name = "${var.env}-eks-oidc"} 
}

//워커 노드가 맡을 역할, 노드가 클러스터에 합류, 이미지를 땡겨오고 네트워킹 하려면 필요함
resource "aws_iam_role" "node" {
  name = "${var.env}-eks-node-role"
  assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }]
    })
}

resource "aws_iam_role" "cluster" {
    name = "${var.env}-eks-cluster-role"

    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
      }]
    })
}

//노드가 클러스터에 합류하고 컨트롤플레인과 통신하는 역할
resource "aws_iam_role_policy_attachment" "node_worker" {
    role       = aws_iam_role.node.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
//vpc-cni가 파드에 vpc id를 부여하려고 할 때 ENI/보조 IP를 붙이는 권한
resource "aws_iam_role_policy_attachment" "node_cni" {
    role       = aws_iam_role.node.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
//ECR에서 컨테이너 이미지 Pull
resource "aws_iam_role_policy_attachment" "node_ecr" {
    role       = aws_iam_role.node.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.env}-eks-ng"
  node_role_arn   =  aws_iam_role.node.arn
  subnet_ids      =  var.private_subnet_ids

  ami_type        =  "AL2023_x86_64_STANDARD"
  instance_types  = var.node_instance_types 
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [ 
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
   ]
   tags = { Name = "${var.env}-eks-ng"}
}
//파드에 VPC IP부여
resource "aws_eks_addon" "vpc_cni" {
    cluster_name = aws_eks_cluster.this.name
    addon_name   = "vpc-cni"
}
// 노드에서 서비스 라우팅 처리
resource "aws_eks_addon" "kube_proxy" {
    cluster_name = aws_eks_cluster.this.name
    addon_name   = "kube-proxy"
}
//클러스터 내부 DNS (서비스 이름 -> IP)
resource "aws_eks_addon" "coredns" {
    cluster_name = aws_eks_cluster.this.name
    addon_name   = "coredns"

    depends_on = [ aws_eks_node_group.default ]
}

