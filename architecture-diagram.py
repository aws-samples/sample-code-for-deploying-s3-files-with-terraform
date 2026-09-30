from diagrams import Cluster, Diagram, Edge
from diagrams.aws.storage import S3, SimpleStorageServiceS3Bucket
from diagrams.aws.compute import EC2, ECS, Lambda
from diagrams.aws.network import VPC, VPCElasticNetworkInterface
from diagrams.aws.security import IAMRole, KMS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.general import GenericFirewall

graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.8",
    "nodesep": "0.6",
    "ranksep": "1.2",
}

with Diagram(
    "Amazon S3 Files — Terraform Deployment Architecture",
    filename="architecture-diagram",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):

    # Supporting services at the top
    with Cluster("Management & Security"):
        cloudwatch = Cloudwatch("CloudWatch\nMonitoring")
        kms = KMS("KMS Key\n(Encryption)")
        iam = IAMRole("IAM Policies")

    with Cluster("Amazon VPC", graph_attr={"bgcolor": "#E8F4FD", "style": "rounded"}):

        with Cluster("Availability Zone A", graph_attr={"bgcolor": "#F0F8E8"}):
            with Cluster("Private Subnet A"):
                mount_target_a = VPCElasticNetworkInterface("Mount Target A\nNFS:2049")
                ec2_a = EC2("EC2 Instance")
                ecs_a = ECS("ECS Fargate\nTask")

        with Cluster("Availability Zone B", graph_attr={"bgcolor": "#F0F8E8"}):
            with Cluster("Private Subnet B"):
                mount_target_b = VPCElasticNetworkInterface("Mount Target B\nNFS:2049")
                ec2_b = EC2("EC2 Instance")
                lambda_b = Lambda("Lambda\nFunction")

    # S3 File System and Bucket at the bottom
    s3_files = S3("S3 File System\n(NFS v4.1+)")
    s3_bucket = SimpleStorageServiceS3Bucket("S3 Bucket\n(General Purpose)")

    # Compute to mount targets
    ec2_a >> Edge(label="NFS v4.1", color="darkgreen") >> mount_target_a
    ecs_a >> Edge(label="NFS v4.1", color="darkgreen") >> mount_target_a

    ec2_b >> Edge(label="NFS v4.1", color="darkgreen") >> mount_target_b
    lambda_b >> Edge(label="NFS v4.1", color="darkgreen") >> mount_target_b

    # Mount targets to file system
    mount_target_a >> Edge(color="#0073BB", style="bold") >> s3_files
    mount_target_b >> Edge(color="#0073BB", style="bold") >> s3_files

    # File system to bucket (bidirectional sync)
    s3_files >> Edge(label="  Sync  ", color="#8C4FFF", style="bold") >> s3_bucket
    s3_bucket >> Edge(label="  Sync  ", color="#8C4FFF", style="bold") >> s3_files

    # Supporting services connections
    s3_files - Edge(color="gray", style="dashed") - kms
    s3_files - Edge(color="gray", style="dashed") - iam
    s3_files - Edge(color="gray", style="dashed") - cloudwatch
