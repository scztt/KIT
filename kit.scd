
State(\KIT).clear();

State(\KIT).initActions.add({
	~distBuffer = Buffer.alloc(s, 4092)
	~distBuffer.cheby([3.1, 0, 1.6, -1, 1,], asWavetable:true);
	~distBuffer.cheby([3.1, 0, 1.6], asWavetable:true);
	~resources.add(~distBuffer);

	~controls = (
		\kit: (
			\
		)
	)
});

State(\KIT).startActions.add({
	Ndef(\mbdistNotes, {
		var notes, nTop;
		nTop		= TWChoose.kr(Dust.kr(14.9), [50, 57], [1, 0.5], 1);
		notes		= [50.04, 50, 57.5, 57.10, nTop + 24, nTop].midicps;
		notes 		= notes ++ [44, 44].midicps;

		notes		= ([25, 50, 50, 50] * 2 * SinOsc.kr(LFNoise2.kr(3, 0.2, 0.2), 0, 1.5, 2.0).round)
		++ ([50, 75, 50 * 2, 50] * 8 * 1 / 4);

		notes 		= ((30 + 12 + [	0, 	0.001, 	7, 		12	]).midicps * SinOsc.kr(LFNoise2.kr(3, 5, 5.2), 0, 0.5, 1.5).round)
		++ (30 + 24 + [	0, 	7, 		20,	 	12  ]).midicps
	});

	s.sync();

	~distFunc = {
		|sig, boost = 10, splitFuncs|
		var splitSigs, split, feed;

		splitSigs = List();

		splitFuncs.do {
			|splitFunc|
			var split = splitFunc.value(sig);
			splitSigs.add(split);
			sig = sig - split;
		};
		splitSigs.add(sig);

		splitSigs = splitSigs.collect {
			|split|
			split = DistCurve(\box).ar(split, 1, boost, 1);
			// split = split + Convolution2.ar(split, ~conv.bufnum);
		};

		Mix(splitSigs);
	};

	Ndef(\mbdist, {
		var feed, sig, sigLo, sigHi, freqs, trig, trig2, notes,
		buzz, impulse, thump, thumpTrig;

		////////////// FEEDBACK
		feed		= LocalIn.ar(2).neg;
		feed		= Balance2.ar(feed[0], feed[1], SinOsc.ar(\panSpeed.kr(0.1, 0.5)));
		feed		= DelayC.ar(feed, 2, 2);
		feed 		= LPF.ar(feed, \feedCutoff.kr(1250, 0.3));
		feed 		= HPF.ar(feed, 40);
		feed		= Compander.ar(feed, feed, \feedThreshold.kr(0.1), 1 / 8, 1 / 50) * 0.1;
		feed 		= feed.tanh.neg;

		////////////// TRIGGERING
		trig2		= Impulse.ar(2.pow(\trig2F.kr(-4)));
		trig		= Impulse.ar(2.pow(\trigF.kr(2))) * 0.4;
		trig		= (trig
			+ CombC.ar(trig, 1, 2.pow(\comb1F.kr(-2)), LFNoise2.kr(1).pow(2).max(0), 1)
			+ CombC.ar(trig, 1, 2.pow(\comb2F.kr(-3)), LFNoise2.kr(1).pow(2).max(0), 1)
		);


		////////////// PLUCK
		notes 		= Ndef(\mbdistNotes).kr();
		sig			= Pluck.ar(feed.neg + LPF.ar({ Dust.ar(50) }, 900), trig, 0.4, notes.reciprocal, 0.7, 0.1);
		sig			= (sig * 0.5) + Pluck.ar(sig.sum, trig2, 0.4, notes.reciprocal, 40, 0.4);
		sig			= (sig * 0.5) + RLPF.ar(sig, notes * 2, 200 / notes);
		sig			= (sig * 10) + (feed * 1);
		sig.assertChannels(notes.size);

		////////////// DISTORTION
		sig 		= notes.sum {
			|f, i|
			var bandSig, width, amp;
			bandSig 	= (LeakDC.ar(sig[i])
				* LPF.ar(
					in: Decay2.ar(
						in: 		trig,
						attackTime:	TRand.ar(0.001, \attackTime.kr(0.1, 0.5), trig),
						decayTime:	TExpRand.ar(0.1, \decayTime.kr(1, 0.5), trig),
					),
					freq: 	1500,
					mul:	6
				)
			);
			bandSig		= ~distFunc.(bandSig, \boost.kr(5));

			bandSig		= (bandSig * 0.6) + (
				bandSig * Splay.ar(8.collect {
					//var f = LFDNoise3.ar(Decay2.ar(trig, 1, 8, 0.01), 780, 800);
					var f 	= SinOsc.ar(Decay2.ar(trig, 1, 8, 0.01), Rand(0, 2), 780, 800);
					BPF.ar(bandSig, f, \sweepBW.kr(50) / f, 100).tanh;
				})
			);

			bandSig		= Shapesdar.ar(~distBuffer.bufnum, bandSig) * 10;
			bandSig		= Compander.ar(bandSig, bandSig * 6, 0.5, 1, 1 / 10);
			bandSig		= \bandsAmp.kr(0.15) * LPF.ar(bandSig, 15000);
		};
		sig.assertChannels(2);

		////////////// PERC
		impulse		= (LPF.ar(Decay2.ar(Impulse.ar(1, 0), 0.001, 0.4), 300, 1)).tanh;

		thumpTrig 	= Decay2.ar((Impulse.ar(2) * WhiteNoise.ar.abs) > 0.5, 0.1, 0.4);
		thump		= SinOsc.ar(thumpTrig.linlin(0, 1, 10, TRand.ar(80, 60, sTrig)), sTrig, sTrig * 24).tanh;

		buzz		= { BBandPass.ar((WhiteNoise.ar * trig.min(1)) > 0.999, 20, 0.1, 14000).fold(-0.5, 0.5).tanh } ! 2;

		sig			= sig + sum(
			(\impulseAmp.kr(1, 0.5) * impulse),
			(\thumpAmp.kr(1, 0.5) * thump),
			(\buzzAmp.kr(1, 0.5) * buzz),
		);

		LocalOut.ar(sig);
		sig			= Compander.ar(sig, sig, 0.5, 1 / 8, 1 / 45, 0.001, 0.1);
	});

	Ndef(\mbdist).setControls(
		// ...
	);
});

State(\KIT).stopActions.add({

});

State(\KIT).freeActions.add({

});


(
)

(


);
Ndef(\mbdist).play
Ndef(\mbdist).fadeTime = 4;

~lc = LCDevice();
~lc.connect();

~lc.knobRows[3][0].cv.action_({
	|cv|
	Ndef(\mbdist).set(\feedCutoff, cv.value);
});
~lc.knobRows[3][1].cv.action_({
	|cv|
	Ndef(\mbdist).set(\bandsAmp, cv.value);
});
~lc.knobRows[3][2].cv.action_({
	|cv|
	Ndef(\mbdist).set(\boost, cv.value);
});

~lc.knobRows[3][0].cv.spec_(ControlSpec(100, 8000, default:1250));
~lc.knobRows[3][1].cv.spec_(ControlSpec(0.0, 1, warp: 4, default:0.15));
~lc.knobRows[3][2].cv.spec_(ControlSpec(0.1, 15, warp: 1, default:5));

AudioCaptureView(\kit).front;