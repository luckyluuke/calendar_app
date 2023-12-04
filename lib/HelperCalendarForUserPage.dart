import 'dart:convert';
import 'dart:core';
import 'dart:io';
//import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:calendar_app/UserManager.dart';
import 'package:calendar_app/enums.dart';



class HelperCalendarForUserPage extends StatefulWidget {
  final String helperId;
  final String helperName;
  final int isHelperCertified;
  final int spotPrice;
  final String helperCountryCode;
  final List addedSpotPrice;


  HelperCalendarForUserPage(this.helperId, this.helperName, this.isHelperCertified, this.spotPrice,this.helperCountryCode,this.addedSpotPrice);

  @override
  _HelperCalendarForUserPageState createState() => _HelperCalendarForUserPageState();
}


class _HelperCalendarForUserPageState extends State<HelperCalendarForUserPage> {

  _HelperCalendarForUserPageState(){
    _selectedDay = listOfDays.elementAt(DateTime.now().weekday - 1);
  }


  static const List<String> listOfDays = ["lundi","mardi","mercredi","jeudi","vendredi","samedi","dimanche"];

  String? _selectedDay;
  List listOfLives = [];
  UserManager _userManager = UserManager();
  late TextEditingController userMailController = TextEditingController();
  String currentUserMail = "";
  bool showLoadingAnimation = false;
  bool buttonPressed = false;
  late Future<List> _displayScheduledLives;


  @override
  void initState() {
    super.initState();
    _displayScheduledLives = displayScheduledLives();

  }

  int getSpotDateInMilliseconds(String selectedTime){
    int scheduledSpotCheckerInMilliseconds = 0;
    List<String> timeDecomposed = selectedTime.split("-");
    String scheduledHourStr = timeDecomposed[0].split("h").first;
    var scheduledHourInt = int.parse(scheduledHourStr);
    var currentDate = DateTime.now();
    String formattedMonth = (currentDate.month < 10) ? "0"+currentDate.month.toString() : currentDate.month.toString();
    String  formattedDay = (currentDate.day < 10) ? "0"+currentDate.day.toString() : currentDate.day.toString();
    var date =  currentDate.year.toString() + "-" + formattedMonth + "-" + formattedDay + " " + scheduledHourStr + ":00:00";
    var millisecondsInOneDay = (86400 * 1000);
    int maxDays = 7;

    if(listOfDays.elementAt(currentDate.weekday - 1) == _selectedDay!){
      if(currentDate.hour < scheduledHourInt){
        scheduledSpotCheckerInMilliseconds = DateTime.parse(date).millisecondsSinceEpoch + millisecondsInOneDay;
      }else{
        scheduledSpotCheckerInMilliseconds = DateTime.parse(date).millisecondsSinceEpoch + (millisecondsInOneDay * 7) + millisecondsInOneDay;
      }
    }else{
      int selectedWeekDay = listOfDays.indexOf(_selectedDay!);
      if((currentDate.weekday - 1) < selectedWeekDay){
        scheduledSpotCheckerInMilliseconds = DateTime.parse(date).millisecondsSinceEpoch + ((selectedWeekDay + 1) - currentDate.weekday) * millisecondsInOneDay + millisecondsInOneDay;
      }else{
        int delta = maxDays - currentDate.weekday;
        scheduledSpotCheckerInMilliseconds = DateTime.parse(date).millisecondsSinceEpoch + (delta * millisecondsInOneDay) + ((selectedWeekDay + 1) * millisecondsInOneDay) + millisecondsInOneDay;
      }
    }

    return scheduledSpotCheckerInMilliseconds;
  }

  Future<List> displayScheduledLives() async {

    Map neededParams = {
      //CommonFunctionsManager.getDayTranslation(_selectedDay!):"",
    };

    Map parameters = {
      "advancedMode":false,
      "docId":widget.helperId,
      "collectionName":"allScheduledLives",
      "neededParams": json.encode(neededParams),
    };

    var tmpResult = await _userManager.callCloudFunction("getUserInfo", parameters);
    List result = tmpResult.data[0/*CommonFunctionsManager.getDayTranslation(_selectedDay!)*/];

    //List result = querySnapshot.get(CommonFunctionsManager.getDayTranslation(_selectedDay!));
    result = result.where((element) => ("cannotDelete" == element.split("|").elementAt(1))).toList();
    return result;
  }

  Future<bool> displayPaymentSheet(String scheduledTime) async {
    bool paymentSuccess = false;
    try {
      await Stripe.instance.presentPaymentSheet();

      /*The part below is triggered only if "Stripe.instance.presentPaymentSheet()" has succeedeed,
      that means the user has successfully paid ! */
      paymentSuccess = true;

      if(currentUserMail.isEmpty){
        await _userManager.updateMultipleValues(
            "allUsers",
            {
              'is_new_user': false,
              'customerEmail':userMailController.text.trim().toLowerCase()
            });
      }

      //Navigator.pop(context);

    } on Exception catch (e) {
      paymentSuccess = false;
      if (e is StripeException) {
        print("Error from Stripe: ${e.error.localizedMessage}");
      } else {
        print("Unforeseen error: ${e}");
      }
    } catch (e) {
      paymentSuccess = false;
      print("exception:$e");
    }

    return paymentSuccess;
  }

  Future<bool> makePayment(
      {required String amount, required String currency, required String scheduledTime, required String email, required String helperId, required String scheduledDay, required bool renewPayment, required int scheduledSpotCheckerTime}) async {

    bool paymentSuccess = false;
    Map<String, dynamic>? paymentIntentData;
    try {

      HttpsCallable stripePaymentIntentCallable = await FirebaseFunctions.instanceFor(app: FirebaseFunctions.instance.app, region: "europe-west1").httpsCallable('stripePaymentIntent');

      final resp = await stripePaymentIntentCallable.call(<String, dynamic>{
        "amount":amount,
        "currency":currency,
        "userId":_userManager.userId,
        "email":email,
        "helperId":helperId,
        "scheduledDay":scheduledDay,
        "scheduledHour":scheduledTime,
        "renewPayment":renewPayment.toString(),
        "scheduledSpotCheckerTime": scheduledSpotCheckerTime.toString()
      });

      paymentIntentData = resp.data;

      if (paymentIntentData != null) {

        await Stripe.instance.initPaymentSheet(
            paymentSheetParameters: SetupPaymentSheetParameters(
              merchantDisplayName: 'Oskour',
              customerId: paymentIntentData!['customer'],
              paymentIntentClientSecret: paymentIntentData!['client_secret'],
              customerEphemeralKeySecret: paymentIntentData!['ephemeralKey'],
              billingDetails: BillingDetails(
                //name: pseudo,
                  email: currentUserMail.isNotEmpty ? currentUserMail : userMailController.text.trim().toLowerCase()
              )
            ));

        setState(() {
          showLoadingAnimation = false;
        });

        paymentSuccess = await displayPaymentSheet(scheduledTime);
        return paymentSuccess;

      }else{
        debugPrint("DEBUG_LOG Le paiement ne peut se faire.");
        return paymentSuccess;
      }
    } catch (e, s) {
      print('exception:$e$s');
      return paymentSuccess;
    }
  }

  Future<String> showEmailPopUp() async {
    String userEmail = "";
    await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Etape 1/2: Inscris ton email"),
            content: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(3),
                      decoration:
                      BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(5)
                      ),
                      child: Row(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 200,
                                height: 40,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: Colors.white),
                                child: TextField(
                                  controller: userMailController,
                                  decoration: InputDecoration(
                                    hintText: "john@gmail.com",
                                    hintMaxLines: 2,
                                    hintStyle: TextStyle(
                                        fontSize: 15,
                                        fontStyle: FontStyle.italic
                                    ),
                                    contentPadding: EdgeInsets.all(10),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ),
            actions: [
              Center(
                child: ElevatedButton(
                    onPressed:() {
                      userEmail = userMailController.text.trim();
                      if(userEmail.contains("@")){
                        Navigator.pop(context);
                      }else if(userEmail.isEmpty){
                        userEmail = "";
                        //AlertDialogManager.shortDialog(context, "L'adresse email ne peut pas être vide.");
                      }else {
                        userEmail = "";
                        //AlertDialogManager.shortDialog(context, "L'adresse email contient une erreur.");
                      }

                    },
                    style: ElevatedButton.styleFrom(
                      shape: StadiumBorder(),
                      primary: Colors.green,
                    ),
                    child:
                    Text(
                      "Valider",
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                ),
              ),
            ],
          );
        });
    return userEmail;
  }

  Future<int> showSpotPriceSelection(List addedSpotPrice, String countryCode) async {
    var firstSpot = addedSpotPrice[0].split("|");
    String selectedSpotPrice = firstSpot[0];
    String selectedSpot = firstSpot[1];

    int platformFee = 0;//CommonFunctionsManager.convertCurrency(5.0 , countryCode, false);
    var currency = g_helperSpotPriceCurrencies[countryCode][1];

    await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (context,refresh) {

                return AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0)
                  ),
                  title: Text(
                    "Les tarifs de " + widget.helperName,
                    style: GoogleFonts.inter(
                      color: Colors.green,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Sélectionne ton niveau:",
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontSize: 18,
                          //fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                          children: addedSpotPrice.map((element) {
                            var spot = element.split("|");
                            String spotPriceSelection = spot[0];
                            String spotNameSelection = spot[1];

                            int spotExchange = 0;//CommonFunctionsManager.convertCurrency(double.parse(spotPriceSelection) - 5.0 , countryCode, false);

                            return InkWell(
                              onTap:(){
                                refresh((){
                                  selectedSpot = spotNameSelection;
                                  selectedSpotPrice = spotPriceSelection;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      height:30,
                                      width: 30,
                                      child: (selectedSpot == spotNameSelection) ? Icon(Icons.keyboard_arrow_right,size: 30) : null
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: (selectedSpot == spotNameSelection) ?  Colors.lightBlueAccent : Colors.orange,
                                        border: Border.all(color: (selectedSpot == spotNameSelection) ? Colors.blue: Colors.black,width: (selectedSpot == spotNameSelection) ? 5 : 1),
                                        borderRadius: BorderRadius.circular(30.0),
                                      ),
                                      width: 150,
                                      height: 50,
                                      child: Column(children: [
                                        Text(
                                          spotNameSelection,
                                          style: GoogleFonts.inter(
                                            color: Colors.black,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          spotExchange.toString() + currency,
                                          style: GoogleFonts.inter(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      ]),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList()
                      ),
                      SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: RichText(
                            text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: "+ Garantie Oskour incluse ✅\n",
                                    style: GoogleFonts.inter(
                                      color: Colors.blue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: "(vous êtes remboursé si le spot n'a pas lieu ou si vous décidez d'annuler la réservation)",
                                    style: GoogleFonts.inter(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ]
                            )
                        ),
                      ),
                      SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: RichText(
                            text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: "+ Frais de service ",
                                    style: GoogleFonts.inter(
                                      color: Colors.blue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: "(" + platformFee.toString() + currency + ")",
                                    style: GoogleFonts.inter(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ]
                            )
                        ),
                      ),
                      SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          InkWell(
                            onTap: (){
                              Navigator.pop(context);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                  color: Colors.green,
                                  border: Border.all(color: Colors.black,width: 2),
                                  borderRadius: BorderRadius.circular(30.0),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.grey,
                                        blurRadius: 4,
                                        offset: Offset(0, 3)
                                    ),
                                  ]
                              ),
                              width: 100,
                              height: 25,
                              child: Text(
                                  "Réserver",
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  )
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
          );
        }
    );

    return int.parse(selectedSpotPrice);
  }

  List setPrice(String countryCode, int spotPriceChoice){
    bool isAfricanCountry = g_africanCountriesCurrencies.keys.contains(countryCode);
    bool isHelperEuropeanCountry = g_europeCountriesCurrencies.keys.contains(widget.helperCountryCode);

    int realHelperPrice = isAfricanCountry ? (isHelperEuropeanCountry ? CountrySpotMinimumPrice.AFRICA :  spotPriceChoice) : ((isHelperEuropeanCountry ? spotPriceChoice :  CountrySpotMinimumPrice.EUROPE));
    int temporaryPrice = realHelperPrice - 5;
    int helperPriceDisplay = /*(temporaryPrice < 0 ?*/ 0; //: CommonFunctionsManager.convertCurrency(temporaryPrice.toDouble(), countryCode, false));

    String helperPrice = "";

    if(isAfricanCountry && (countryCode != "TN") && (countryCode != "DZ") && (countryCode != "CD") && (countryCode != "MA")){
      //helperPrice = CommonFunctionsManager.convertCurrency(realHelperPrice.toDouble(), countryCode, false).toString();
    }else{
      if((countryCode == "DZ") || (countryCode == "CD") || (countryCode == "MA") || (countryCode == "CH")){
        //helperPrice = (CommonFunctionsManager.convertCurrency(realHelperPrice.toDouble(), countryCode, false) * 100).toString();
      }else{
        helperPrice = (realHelperPrice * 100).toString();
      }
    }
    return [helperPriceDisplay,helperPrice];
  }

  @override
  Widget build(BuildContext context) {
    //debugPrint("DEBUG_LOG CURRENT DAY:" + _selectedDay!);
    return Scaffold(
        appBar: AppBar(
          title: FittedBox(
            child: Text("Réserver un SPOT avec " + widget.helperName,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              ),
            ),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.yellow,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded ,
              color: Colors.black,
              size: 30,
            ),
            onPressed: () {
            Navigator.pop(context);
            },
          ),
        ),
        body:Stack(
          children: [
            Column(
              children: [
                SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: listOfDays.map(
                    (element) {
                      return Row(
                        children: [
                          InkWell(
                            onTap:(){
                              setState(() {
                                _selectedDay = element;
                                _displayScheduledLives = displayScheduledLives();
                              });

                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration:  BoxDecoration(
                                color: (element == _selectedDay) ? Colors.blueAccent : Colors.grey,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Center(
                                  child: Text(
                                    element.substring(0,3) +".",
                                    style: (element == _selectedDay) ? GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ) : null,
                                  )
                              ),
                            ),
                          ),
                          SizedBox(width: 5),
                        ],
                      );
                    }
                  ).toList(),
                ),
                SizedBox(height: 20),
                Container(
                  child: Text(
                      (listOfDays.elementAt(DateTime.now().weekday - 1) == _selectedDay!) ?
                          "AUJOURD'HUI": _selectedDay!.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: Colors.blue,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      )
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child:
                    FutureBuilder<List?>(
                        future: _displayScheduledLives,
                        builder: (context, AsyncSnapshot<List?> snapshot) {

                          if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty){
                            List listOfLivesForHelperSelectedDay = snapshot.data!;
                            return Container(
                              child: DataTable(
                                  columns: const <DataColumn>[
                                    DataColumn(
                                      label: Text(
                                        'Horaires',
                                        style: TextStyle(fontStyle: FontStyle.italic),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        "Disponibilités",
                                        style: TextStyle(fontStyle: FontStyle.italic),
                                      ),
                                    ),
                                  ],
                                  rows: listOfLivesForHelperSelectedDay.map(
                                          (element){
                                         List params = element.split("|");
                                         String time = params.elementAt(0);
                                         String scheduledUser = (params.length > 3 ) ? params.elementAt(3) : "";
                                        return DataRow(
                                          cells: <DataCell>[
                                            DataCell(Text(time)),
                                            DataCell(
                                              (scheduledUser.isEmpty) ?
                                              Center(
                                                child:
                                                ElevatedButton(
                                                    onPressed:() async {

                                                      if(_userManager.userId != widget.helperId){
                                                        List listOfNeededParams = ["pseudo","customerEmail","countryCode"];
                                                        Map tmpValues = await _userManager.getMultipleValues("allUsers", listOfNeededParams);
                                                        var currentUserPseudo  = tmpValues[listOfNeededParams[0]];
                                                        currentUserMail = tmpValues[listOfNeededParams[1]];
                                                        var countryCode = tmpValues[listOfNeededParams[2]];

                                                        String currency = "eur";

                                                        if(g_africanCountriesCurrencies.keys.contains(countryCode)){
                                                          List resultInfo = g_africanCountriesCurrencies[countryCode];
                                                          currency = resultInfo[0];
                                                        }else if(g_europeCountriesCurrencies.keys.contains(countryCode)){
                                                          List resultInfo = g_europeCountriesCurrencies[countryCode];
                                                          currency = resultInfo[0];
                                                        }

                                                        List resultPriceBasic = setPrice(countryCode, widget.spotPrice);
                                                        int helperPriceDisplay = resultPriceBasic[0];
                                                        String helperPrice = resultPriceBasic[1];

                                                        Map results = {};//await AlertDialogManager.showReservationLiveDialog(context, _userManager.userId!, currentUserPseudo, widget.helperName, widget.helperId, _selectedDay!, time, element, setState, listOfLivesForHelperSelectedDay, widget.isHelperCertified, helperPriceDisplay,countryCode);


                                                        bool? status = results["status"];
                                                        bool paymentSuccess = false;

                                                        if ((status != null) && status){

                                                          List addedSpotPriceUpdated = [widget.spotPrice.toString()+"|"+"Basique"];
                                                          addedSpotPriceUpdated.addAll(widget.addedSpotPrice);
                                                          int selectedSpotPriceFromDialog = await showSpotPriceSelection(addedSpotPriceUpdated,countryCode);
                                                          List resultPriceUpdated = setPrice(countryCode,selectedSpotPriceFromDialog);
                                                          helperPriceDisplay = resultPriceUpdated[0];
                                                          helperPrice = resultPriceUpdated[1];


                                                          int scheduledSpotCheckerTime = getSpotDateInMilliseconds(time);
                                                          if(currentUserMail.isEmpty){
                                                            String currentUserMailValue = await showEmailPopUp();
                                                            if(currentUserMailValue.isNotEmpty) {
                                                              setState(() {
                                                                showLoadingAnimation = true;
                                                              });
                                                              paymentSuccess = await makePayment(amount:helperPrice,currency: currency,scheduledTime: time, email: currentUserMailValue,helperId: widget.helperId, scheduledDay: "Monday"/*CommonFunctionsManager.getDayTranslation(_selectedDay!)*/,renewPayment:results["accepted"],scheduledSpotCheckerTime: scheduledSpotCheckerTime);
                                                            }else{
                                                              return;
                                                            }
                                                          }else{
                                                            setState(() {
                                                              showLoadingAnimation = true;
                                                            });
                                                            paymentSuccess = await makePayment(amount:helperPrice,currency: currency,scheduledTime: time, email: currentUserMail, helperId: widget.helperId, scheduledDay: "Monday"/*CommonFunctionsManager.getDayTranslation(_selectedDay!)*/, renewPayment:results["accepted"],scheduledSpotCheckerTime: scheduledSpotCheckerTime);
                                                          }

                                                          if(paymentSuccess){

                                                            setState(() {
                                                              showLoadingAnimation = true;
                                                            });

                                                            bool canScheduleLive = results["canScheduleLive"];
                                                            bool accepted = results["accepted"];
                                                            bool scheduleTimeEmpty = results["scheduleTimeEmpty"];
                                                            bool currentUserTimeExistsAndIsAvailable = results["currentUserTimeExistsAndIsAvailable"];
                                                            bool currentUserTimeExists = results["currentUserTimeExists"];
                                                            List listOfLivesForUserSelectedDay = results["listOfLivesForUserSelectedDay"];
                                                            String userElement = results["userElement"];

                                                            if (scheduleTimeEmpty) {
                                                              String newHelperReservation = element + widget.helperId + "|" + _userManager.userId!;
                                                              List tmp = newHelperReservation
                                                                  .split("|");
                                                              String newLiveReservation = tmp[0] +
                                                                  "|canDelete|" +
                                                                  tmp[2] + "|" + tmp[3];
                                                              /*await _userManager
                                                                  .updateValue(
                                                                  "allScheduledLives",
                                                                  CommonFunctionsManager
                                                                      .getDayTranslation(
                                                                      _selectedDay!),
                                                                  [newLiveReservation]
                                                              );*/
                                                            }
                                                            else {
                                                              List sortedList = !currentUserTimeExists
                                                                  ? [
                                                                g_scheduledLives
                                                                    .indexOf(time)
                                                              ]
                                                                  : [];
                                                              List sortedListOfLivesForUserSelectedDay = [
                                                              ];

                                                              listOfLivesForUserSelectedDay
                                                                  .forEach((element) {
                                                                sortedList.add(
                                                                    g_scheduledLives
                                                                        .indexOf(
                                                                        element.split(
                                                                            "|")
                                                                            .elementAt(
                                                                            0)));
                                                              });
                                                              sortedList.sort();
                                                              sortedList.forEach((
                                                                  index) {
                                                                sortedListOfLivesForUserSelectedDay
                                                                    .add(
                                                                    listOfLivesForUserSelectedDay
                                                                        .singleWhere(
                                                                            (
                                                                            element) =>
                                                                        element.split(
                                                                            "|")
                                                                            .elementAt(
                                                                            0) ==
                                                                            g_scheduledLives
                                                                                .elementAt(
                                                                                index),
                                                                        orElse:
                                                                            () =>
                                                                        (g_scheduledLives
                                                                            .elementAt(
                                                                            index) +
                                                                            "|canDelete|" +
                                                                            widget
                                                                                .helperId + "|" + _userManager.userId!))
                                                                );
                                                              });


                                                              if (currentUserTimeExistsAndIsAvailable) {
                                                                String newHelperReservation = userElement + widget.helperId + "|" + _userManager.userId!;
                                                                sortedListOfLivesForUserSelectedDay[sortedListOfLivesForUserSelectedDay
                                                                    .indexOf(
                                                                    userElement)] =
                                                                    newHelperReservation;
                                                              }

                                                              /*await _userManager
                                                                  .updateValue(
                                                                  "allScheduledLives",
                                                                  CommonFunctionsManager
                                                                      .getDayTranslation(
                                                                      _selectedDay!),
                                                                  sortedListOfLivesForUserSelectedDay
                                                              );*/
                                                            }

                                                            if (canScheduleLive) {
                                                              String newUserReservation = element + widget.helperId + "|" + _userManager.userId!;
                                                              listOfLivesForHelperSelectedDay[listOfLivesForHelperSelectedDay
                                                                  .indexOf(element)] =
                                                                  newUserReservation;

                                                              Map otherParamsToBeUpdated = {
                                                                /*CommonFunctionsManager
                                                                    .getDayTranslation(
                                                                    _selectedDay!): listOfLivesForHelperSelectedDay*/
                                                              };

                                                              Map otherParameters = {
                                                                "advancedMode": false,
                                                                "docId": widget
                                                                    .helperId,
                                                                "collectionName": "allScheduledLives",
                                                                "paramsToBeUpdated": json
                                                                    .encode(
                                                                    otherParamsToBeUpdated),
                                                              };

                                                              await _userManager
                                                                  .callCloudFunction(
                                                                  "updateUserInfo",
                                                                  otherParameters);

                                                              HttpsCallable sendNotificationCallable = await FirebaseFunctions
                                                                  .instanceFor(
                                                                  app: FirebaseFunctions
                                                                      .instance.app,
                                                                  region: "europe-west1")
                                                                  .httpsCallable(
                                                                  'sendNotification');

                                                              String scheduledHour = time
                                                                  .split("-")
                                                                  .elementAt(0).split(
                                                                  "h")
                                                                  .elementAt(0);
                                                              String scheduledDay = "Monday";/*CommonFunctionsManager
                                                                  .getDayTranslation(
                                                                  _selectedDay!);*/
                                                              int tmpDayInt = 1/*CommonFunctionsManager
                                                                  .getDayInt(
                                                                  scheduledDay)*/;
                                                              List generatedNotificationIds = []/*CommonFunctionsManager
                                                                  .getNotificationIdFromTimeScheduled(
                                                                  tmpDayInt,
                                                                  time)*/;
                                                              int notificationId = generatedNotificationIds
                                                                  .elementAt(0);
                                                              int notificationReminderId = generatedNotificationIds
                                                                  .elementAt(1);

                                                              await sendNotificationCallable
                                                                  .call(
                                                                  <String, dynamic>{
                                                                    "type": "ADD_SCHEDULED_RESERVATION",
                                                                    "notificationId": notificationId
                                                                        .toString(),
                                                                    "notificationReminderId": notificationReminderId
                                                                        .toString(),
                                                                    "receiverId": widget
                                                                        .helperId,
                                                                    "peerTemporaryId": _userManager
                                                                        .userId!,
                                                                    "scheduledTime": time,
                                                                    "scheduledDay": scheduledDay,
                                                                    "scheduledHour": scheduledHour,
                                                                    "senderPseudo": currentUserPseudo,
                                                                    "repeat": accepted
                                                                        .toString(),
                                                                    "message": "🎊 @" +
                                                                        currentUserPseudo +
                                                                        " vient de réserver un spot avec toi le " +
                                                                        /*CommonFunctionsManager
                                                                            .getDayTranslationInFrench(
                                                                            scheduledDay)*/ "Lundi" +
                                                                        " entre " +
                                                                        time,
                                                                    "title": "+" + helperPriceDisplay.toString() + "€ avec @"+ currentUserPseudo,
                                                                    "reminderTitle": "🔔 Le SPOT avec " +
                                                                        currentUserPseudo +
                                                                        " débute maintenant !",
                                                                    "reminderMessage": "Es-tu prêt(e) ?",
                                                                  });


                                                              if (Platform.isIOS) {
                                                                HttpsCallable createOwnReservationForIOSCallable = await FirebaseFunctions
                                                                    .instanceFor(
                                                                    app: FirebaseFunctions
                                                                        .instance.app,
                                                                    region: "europe-west1")
                                                                    .httpsCallable(
                                                                    'createOwnReservationForIOS');
                                                                await createOwnReservationForIOSCallable
                                                                    .call(
                                                                    <String, dynamic>{
                                                                      "ownId": _userManager
                                                                          .userId!,
                                                                      "peerTemporaryId": widget
                                                                          .helperId,
                                                                      "scheduledTime": time,
                                                                      "scheduledDay": scheduledDay,
                                                                      "scheduledHour": scheduledHour,
                                                                      "senderPseudo": currentUserPseudo,
                                                                      "repeat": accepted
                                                                          .toString(),
                                                                      "reminderTitle": "🔔 Le SPOT avec " +
                                                                          widget
                                                                              .helperName +
                                                                          " débute bientôt !",
                                                                      "reminderMessage": "Es-tu prêt(e) ?",
                                                                    });
                                                              } else {

                                                                /*await NotificationApi
                                                                    .createScheduledNotificationChannelIsNotHelper(
                                                                    notificationId
                                                                        .toString(),
                                                                    "🔔 Le SPOT avec " +
                                                                        widget
                                                                            .helperName +
                                                                        " débute maintenant !",
                                                                    widget.helperName +
                                                                        " attend ton appel",
                                                                    accepted.toString(),
                                                                    scheduledDay,
                                                                    scheduledHour,
                                                                    notificationPayload: {
                                                                      "peerName": widget
                                                                          .helperName,
                                                                      "peerTemporaryId": widget
                                                                          .helperId
                                                                    }
                                                                );*/

                                                                int reminderPreviousDay = 7/*CommonFunctionsManager
                                                                    .getDayInt(
                                                                    scheduledDay) - 1*/;

                                                                if (reminderPreviousDay ==
                                                                    0) {
                                                                  reminderPreviousDay =
                                                                  7;
                                                                }

                                                                /*await NotificationApi
                                                                    .createScheduledNotificationBasicChannel(
                                                                  notificationReminderId
                                                                      .toString(),
                                                                  "⏳ Ton LIVE approche !",
                                                                  "Es-tu prêt(e) pour ton LIVE avec " +
                                                                      widget
                                                                          .helperName +
                                                                      " demain ?",
                                                                  accepted.toString(),
                                                                  CommonFunctionsManager
                                                                      .getDayName(
                                                                      reminderPreviousDay),
                                                                  scheduledHour,
                                                                  isReminder: true,
                                                                );*/
                                                              }

                                                              /*NotificationApi.createNormalNotificationBasicChannel(
                                                                CommonFunctionsManager.createUniqueNotificationId(),
                                                                "Confirmation de réservation #" + DateTime.now().millisecondsSinceEpoch.toString(),
                                                                "1 x Spot " + CommonFunctionsManager.getDayTranslationInFrench(scheduledDay) + " à " + time.toUpperCase(),
                                                              );*/

                                                              setState(() {
                                                                showLoadingAnimation = false;
                                                              });
                                                            }
                                                          }
                                                        }
                                                      }else{
                                                        //AlertDialogManager.shortDialog(context, "Tu ne peux pas réserver un créneau avec toi-même.");
                                                      }

                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      shape: StadiumBorder(),
                                                      primary: Colors.green,
                                                      shadowColor: Colors.pink
                                                    ),
                                                    child: Text("Réserver",
                                                      style: GoogleFonts.inter(
                                                        color: Colors.white,
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    )
                                                ),
                                              )
                                              :
                                              Center(
                                                child: StatefulBuilder(
                                                    builder: (context, changeState) {
                                                      if (_userManager.userId == scheduledUser){
                                                        return Container(
                                                            padding: EdgeInsets.all(8.0),
                                                            decoration: BoxDecoration(
                                                                color: Colors.yellow[300],
                                                                borderRadius: BorderRadius.circular(30),
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                      color: Colors.grey,
                                                                      blurRadius: 4,
                                                                      offset: Offset(0,3)
                                                                  ),
                                                                ]
                                                            ),
                                                            child: Text("Réservé avec toi",
                                                                style: GoogleFonts.inter(
                                                                  color: Colors.grey[600],
                                                                  fontSize: 15,
                                                                  fontWeight: FontWeight.w500,
                                                                ))
                                                        );
                                                      }
                                                      else
                                                      {
                                                        return Container(
                                                            padding: EdgeInsets.all(8.0),
                                                            decoration: BoxDecoration(
                                                                color: Colors.red,
                                                                borderRadius: BorderRadius.circular(30),
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                      color: Colors.grey,
                                                                      blurRadius: 4,
                                                                      offset: Offset(0,3)
                                                                  ),
                                                                ]
                                                            ),
                                                            child: Text("Réservé",
                                                                style: GoogleFonts.inter(
                                                                  color: Colors.white,
                                                                  fontSize: 15,
                                                                  fontWeight: FontWeight.w500,
                                                                ))
                                                        );
                                                      }

                                                  }
                                                ),
                                              )
                                            ),
                                          ],
                                        );
                                      }).toList()
                              ),
                            );
                          }
                          else{
                            if (snapshot.hasData && snapshot.data != null && snapshot.data!.isEmpty){
                              return Center(
                                  child: FittedBox(
                                      child: Text(widget.helperName + " n'est pas libre le $_selectedDay",
                                      style: GoogleFonts.inter(
                                    color: Colors.black,
                                    fontSize: 15,
                                  ))),
                              );
                            }
                            else
                            {
                              return Center(
                                  child: SizedBox(
                                      width: 40.0,
                                      height: 40.0,
                                      child: const CircularProgressIndicator(
                                        backgroundColor: Colors.yellow,
                                      )
                                  )
                              );
                            }

                          }
                        }
                      )
                    ),
                ),
              ],
            ),
            if(showLoadingAnimation)
              Center(
                  child: Container(
                    width: 200,
                    height: 70,
                    decoration: BoxDecoration(
                        color: Colors.pink,
                        borderRadius: BorderRadius.circular(10)
                    ),
                    child: Column(
                      children: [
                        Text(
                            "Traitement...",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            )

                        ),
                        SizedBox(height:5),
                        SizedBox(
                          width: 30.0,
                          height: 30.0,
                          child: const CircularProgressIndicator(
                            backgroundColor: Colors.yellow,
                          ),
                        ),
                      ],
                    ),
                  )
              )
          ],
        )
    );
  }

}