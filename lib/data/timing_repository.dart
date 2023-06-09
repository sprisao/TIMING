import 'dart:convert';

import 'package:amplify_api/model_mutations.dart';
import 'package:amplify_api/model_queries.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:timing/data/api_service/graphql_queries.dart';
import 'package:timing/models/ModelProvider.dart';
import 'package:timing/models/activity_model.dart';

import '../models/location_model.dart';
import '../models/schedule_model.dart';

class TimingRepository {
  /*Auth CurrentAuthenticatedUser*/
  Future<void> currentUser() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      safePrint('Current user: ${user.userId}');
    } on AuthException catch (e) {
      safePrint(e.message);
    }
  }

  /*Auth SignOut*/
  Future<void> signOut() async {
    try {
      await Amplify.Auth.signOut();
    } on AuthException catch (e) {
      safePrint("Sign out failed: $e");
    }
  }

/*
  User 생성 : 회원가입 하고 로그인 하면 해당 유저의 이메일 주소를 토대로 바로 UserData 생성
  1. 만약 해당 이메일로 생성된 User가 없다면 생성
  2. 만약 해당 이메일로 생성된 User가 있다면 생성하지 않음
*/

  Future<void> initUser() async {
    final user = await Amplify.Auth.getCurrentUser();
    final userId = user.userId;

    try {
      final userAttributes = await Amplify.Auth.fetchUserAttributes();
      for (final element in userAttributes) {
        if (element.userAttributeKey.toString() == "email") {
          final userEmail = element.value;
          final userDataRequest =
              ModelQueries.list(User.classType, where: User.ID.eq(userId));
          final userDataResponse =
              await Amplify.API.query(request: userDataRequest).response;

          if (userDataResponse.data?.items.isEmpty ?? true) {
            final userToCreate = User(id: userId, email: userEmail);
            final userCreateRequest = ModelMutations.create(userToCreate);
            final response =
                await Amplify.API.mutate(request: userCreateRequest).response;

            final createdUser = response.data;
            if (createdUser == null) {
              safePrint('Error creating user: ${response.errors}');
              return;
            }
            safePrint('New user created: ${createdUser.id}');
          }
          safePrint('User already exists: $userId');
        }
      }
    } on ApiException catch (e) {
      safePrint('Failed to initialize user: $e');
    }
  }

  /* 스케쥴 생성 */
  Future<String> createSchedule(
      CreateScheduleModel schedule, Privacy thisPrivacy) async {
    try {
      final currentUser = await Amplify.Auth.getCurrentUser();

      /* Convert DateTime to TemporalDateTime format */
      final TemporalDateTime date = TemporalDateTime(
          DateTime(schedule.date.year, schedule.date.month, schedule.date.day));

      final TemporalDateTime startTime = TemporalDateTime(DateTime(
          schedule.date.year,
          schedule.date.month,
          schedule.date.day,
          schedule.startTime.hour,
          schedule.startTime.minute));
      final TemporalDateTime endTime = TemporalDateTime(DateTime(
          schedule.date.year,
          schedule.date.month,
          schedule.date.day,
          schedule.endTime.hour,
          schedule.endTime.minute));

      Privacy privacy = thisPrivacy;

      List<String> locationList =
          schedule.locationList.map((e) => e.id).toList();
      List<String> activityItemList =
          schedule.activityItemList.map((e) => e.id).toList();

      final userResponse = await Amplify.API
          .query(request: ModelQueries.get(User.classType, currentUser.userId))
          .response;

      final model = Schedule(
          date: date,
          startTime: startTime,
          endTime: endTime,
          privacy: privacy,
          user: userResponse.data as User,
          locationList: locationList,
          activityItemList: activityItemList);
      final request = ModelMutations.create(model);
      final response = await Amplify.API.mutate(request: request).response;

      final createdSchedule = response.data;

      if (createdSchedule == null) {
        safePrint('errors: ${response.errors}');
        return 'Error';
      }

      safePrint(response.data);
      return 'Success';
    } on ApiException catch (e) {
      safePrint('Mutation failed: $e');
      return 'Failed';
    }
  }

  /* 지역 데이터 가져오기 */
  Future<List<LocationModel>> getLocationList() async {
    try {
      var operation = Amplify.API.query(
        request: GraphQLRequest(document: GraphQlQueries.getLocationList),
      );
      var response = await operation.response;
      var data = json.decode(response.data);

      List<LocationModel> locationList = [];

      await data['listLocations']['items'].forEach((element) async {
        LocationModel location = LocationModel.fromJson(element);
        locationList.add(location);
      });

      return locationList;
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
    }
    return [];
  }

  /*AcitivtyCategory with ActivityItem*/

  Future<List<ActivityCategoryModel>> getActivityCatWithItems() async {
    try {
      var operation = Amplify.API.query(
        request: GraphQLRequest(
            document: GraphQlQueries.getActivityCategoryWithItems),
      );
      var response = await operation.response;
      var data = json.decode(response.data);

      List<ActivityCategoryModel> activityCatList = [];

      await data['listActivityCategories']['items'].forEach((element) async {
        ActivityCategoryModel activityCat =
            ActivityCategoryModel.fromJson(element);

        List<ActivityItemModel> activityItemList = [];

        element['activityItems']['items'].forEach((item) {
          ActivityItemModel activityItem = ActivityItemModel.fromJson(item);
          activityItemList.add(activityItem);
        });

        activityCatList.add(
          ActivityCategoryModel(
            id: activityCat.id,
            titleKR: activityCat.titleKR,
            activityItems: activityItemList,
          ),
        );
      });

      return activityCatList;
    } catch (e) {
      rethrow;
    }
  }

  /* Activity 데이터 가져오기 */
  Future<List<ActivityCategory?>> getActivityCatList() async {
    try {
      final request = ModelQueries.list(ActivityCategory.classType);
      final response = await Amplify.API.query(request: request).response;

      final items = response.data?.items;
      if (items == null) {
        safePrint('errors: ${response.errors}');
        return <ActivityCategory?>[];
      }
      return items;
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
    }
    return <ActivityCategory?>[];
  }

  /* ActivityItem 데이터 가져오기 */
  Future<List<ActivityItem?>> getActivityItemList() async {
    try {
      final request = ModelQueries.list(ActivityItem.classType);
      final response = await Amplify.API.query(request: request).response;

      final items = response.data?.items;
      if (items == null) {
        safePrint('errors: ${response.errors}');
        return <ActivityItem?>[];
      }
      return items;
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
    }
    return <ActivityItem?>[];
  }

  Future<void> createActivityItem(
      {required String name,
      required String emoji,
      required String titleKR,
      required String category}) async {
    final String categoryID = category;

    try {
      final categoryResponse = await Amplify.API
          .query(
              request: ModelQueries.get(ActivityCategory.classType, categoryID))
          .response;
      final model = ActivityItem(
          name: name,
          titleKR: titleKR,
          emoji: emoji,
          activityCategory: categoryResponse.data as ActivityCategory);
      final request = ModelMutations.create(model);
      final response = await Amplify.API.mutate(request: request).response;

      final createdActivityItem = response.data;
      if (createdActivityItem == null) {
        safePrint('errors: ${response.errors}');
        return;
      }
      safePrint('Mutation result: ${createdActivityItem.id}');
    } on ApiException catch (e) {
      safePrint('Mutation failed: $e');
    }
  }

  Future<void> createLocationItem(
      {required String name,
      required String titleEN,
      required String titleKR}) async {
    const String provinceId = "6f490f64-6d04-4a5f-8de9-d0eb09f477cb";

    try {
      final provinceResponse = await Amplify.API
          .query(request: ModelQueries.get(Province.classType, provinceId))
          .response;
      final model = Location(
          name: name,
          titleEN: titleEN,
          titleKR: titleKR,
          province: provinceResponse.data as Province);
      final request = ModelMutations.create(model);
      final response = await Amplify.API.mutate(request: request).response;

      final createdLocation = response.data;
      if (createdLocation == null) {
        safePrint('errors: ${response.errors}');
        return;
      }
      safePrint('Mutation result: ${createdLocation.id}');
    } on ApiException catch (e) {
      safePrint('Mutation failed: $e');
    }
  }

  Future<List<ScheduleModel>> getMyScheduleList() async {
    try {
      AuthUser authUser = await Amplify.Auth.getCurrentUser();
      var operation = Amplify.API.query(
        request: GraphQLRequest(
            document: GraphQlQueries.getScheduleByUserID,
            variables: {'userID': authUser.userId}),
      );
      var response = await operation.response;
      safePrint('Query result: ${response.data}');
      var data = json.decode(response.data);

      List<ScheduleModel> scheduleList = [];

      await data['schedulesByUserID']['items'].forEach((element) async {
        ScheduleModel schedule = ScheduleModel.fromJson(element);
        scheduleList.add(schedule);
      });

      return scheduleList;
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
    }
    return [];
  }
}
