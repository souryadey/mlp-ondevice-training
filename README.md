# mlp-ondevice-training
This repository implements  **on-device training and inference of a multi-layer perceptron** neural network on an FPGA board  -- as per research done by the [USC HAL team](https://hal.usc.edu/).

This  **research paper**  has more details. Please consider citing it if you use or benefit from this work:  
Sourya Dey, Diandian Chen, Zongyang Li, Souvik Kundu, Kuan-Wen Huang, Keith M. Chugg, Peter A. Beerel, "A Highly Parallel FPGA Implementation of Sparse Neural Network Training" in  _International Conference on ReConFigurable Computing and FPGAs (ReConFig)_, Cancun, Mexico, 2018, pp. 1-4.
Available as a short paper on [IEEE](https://ieeexplore.ieee.org/document/8641739)  and full version on [arXiv](https://arxiv.org/abs/1806.01087).

(Additional contributors who are not authors of the paper: Yinan Shao, Nishanth Narisetty, Mahdi Jelodari Mamaghani)

Main folder: `DNN_MNIST_withUART`
Tested and run using Xilinx Vivado.

Complete (and extremely specific) documentation is available [here](https://www.evernote.com/shard/s429/sh/617d573d-c6c0-46fd-ba92-53df0ba085c7/a4d5ad08cb8c004cf8a5f5e80a5d2514). This refers to the [original repository](https://github.com/usc-hal/dnn-rtl) internal to USC HAL (please [contact Sourya Dey](mailto:sourya.dey@gmail.com) for access). This repository is a simplified version of the original.
