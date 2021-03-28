# DetectionAndTracking_iOS
Simple Online Realtime Multi-object detection and tracking on mobile device of iOS  
____
Test on iPhone8(_Test video was token with **`Horizontal screen`**-Orientation_)  
  ![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/objectTracking.gif)
## Tracking Flow(Tracking-by-Detection)
* **Three parts**: **`Detector`**|**`Tracker`**|**`Data Association`**  
![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/trackingFlow.png)

1. **Detector**
    1. Training with Tensorflow Object Detection API using Google Colab
    2. Training with Create ML
    3. Download from [Core ML research community](https://developer.apple.com/machine-learning/models/) 
2. **Tracker**
    1. Single object tracking(Online visual tracking)
![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/BasicFramework.png)
    3. Multi-object tracking
        1. Detector based tracking model
        2. Detector-independent tracking model
4. **Data Association**
    1. [Hungarian Maximum Matching Algorithm](https://brilliant.org/wiki/hungarian-matching/)
    2. Nearest Neighbor Filter
