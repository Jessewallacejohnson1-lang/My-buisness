"""Remakes realesrgan-x4plus-anime.onnx (sources/scripts/sharpen.py's model) from Real-ESRGAN's own weights, on a Mac
with torch and onnx installed (only this script needs them; the morning job runs the .onnx on onnxruntime).

  curl -LO https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth
  # sha256 f872d837d3c90ed2e05227bed711af5671a6fd1c9f7d7e91c911a61f155e99da
  python3 convert_realesrgan.py RealESRGAN_x4plus_anime_6B.pth realesrgan-x4plus-anime.onnx

The network is Real-ESRGAN's RRDBNet with 6 blocks (BSD-3-Clause, xinntao/Real-ESRGAN): RGB 0..1 in, 4x out.
"""
import sys

import torch
from torch import nn
from torch.nn import functional as F


class Dense(nn.Module):
    def __init__(self, feat=64, grow=32):
        super().__init__()
        self.conv1, self.conv2, self.conv3, self.conv4 = (nn.Conv2d(feat + i * grow, grow, 3, 1, 1) for i in range(4))
        self.conv5 = nn.Conv2d(feat + 4 * grow, feat, 3, 1, 1)

    def forward(self, x):
        xs = [x]
        for conv in (self.conv1, self.conv2, self.conv3, self.conv4):
            xs.append(F.leaky_relu(conv(torch.cat(xs, 1)), 0.2))
        return self.conv5(torch.cat(xs, 1)) * 0.2 + x


class RRDB(nn.Module):
    def __init__(self):
        super().__init__()
        self.rdb1, self.rdb2, self.rdb3 = Dense(), Dense(), Dense()

    def forward(self, x):
        return self.rdb3(self.rdb2(self.rdb1(x))) * 0.2 + x


class RRDBNet(nn.Module):
    def __init__(self, blocks=6):
        super().__init__()
        self.conv_first = nn.Conv2d(3, 64, 3, 1, 1)
        self.body = nn.Sequential(*(RRDB() for _ in range(blocks)))
        self.conv_body, self.conv_up1, self.conv_up2, self.conv_hr = (nn.Conv2d(64, 64, 3, 1, 1) for _ in range(4))
        self.conv_last = nn.Conv2d(64, 3, 3, 1, 1)

    def forward(self, x):
        feat = self.conv_first(x)
        feat = feat + self.conv_body(self.body(feat))
        for up in (self.conv_up1, self.conv_up2):
            feat = F.leaky_relu(up(F.interpolate(feat, scale_factor=2, mode="nearest")), 0.2)
        return self.conv_last(F.leaky_relu(self.conv_hr(feat), 0.2))


if __name__ == "__main__":
    net = RRDBNet()
    net.load_state_dict(torch.load(sys.argv[1], map_location="cpu", weights_only=True)["params_ema"])
    net.eval()
    torch.onnx.export(net, torch.rand(1, 3, 64, 64), sys.argv[2], input_names=["image"], output_names=["x4"],
                      dynamic_axes={"image": {2: "h", 3: "w"}, "x4": {2: "h4", 3: "w4"}}, opset_version=17, dynamo=False)
    print("wrote", sys.argv[2])
