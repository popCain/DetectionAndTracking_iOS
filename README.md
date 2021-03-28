# DetectionAndTracking_iOS
Simple Online Realtime Multi-object detection and tracking on mobile device of iOS(*As multiple detected targets enter and exit the frame, unique IDs are created and deleted, and trajectories are created and implemented on iOS for long-term tracking*)  

Test on `iPhone8`(_Test video was token with **`Horizontal screen`**-Orientation_)  
  ![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/objectTracking.gif)
## Tracking Flow(Tracking-by-Detection)
Detector-based data association multi-object tracking
* **Three parts**: **`Detector`**|**`Tracker`**|**`Data Association`**  
![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/trackingFlow.png)

1. **Detector**
    1. Training with Tensorflow Object Detection API using Google Colab
    2. Training with Create ML
    3. Download from [Core ML research community](https://developer.apple.com/machine-learning/models/) 
2. **Tracker( ii-a. )**
    1. Single object tracking(*Basic framework of online visual tracking*)
![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/BasicFramework.png)
    3. **`Multi-object tracking`**
        1. **`Detector-independent tracking model`***(Simply a collection of single object trackers)*
            * Reference of [`tracking in Vision of Core ML`](https://developer.apple.com/documentation/vision/tracking_multiple_objects_or_rectangles_in_video)
                > *Collection of requests: one tracking request per tracked object - 1to1*  
                > Limits:
                >> Number of trackers: 16
            * Reference of OpenCV multi-object tracker
                > *Collection of single object trackers: BOOSTING, MIL, KCF, TLD, MOSSE, CSRT, MEDIANFLOW, GOTURN*
        2. Detector-based tracking model(*Detector-based data association multi-object tracking of `this repository`*)
4. **Data Association**
    1. Optimized Data Association Algorithm
        1. [Hungarian Maximum Matching Algorithm](https://brilliant.org/wiki/hungarian-matching/)
        2. Nearest Neighbor Filter
    2. Data Association Cost
        1. Appearance Features
        2. Motion Features
